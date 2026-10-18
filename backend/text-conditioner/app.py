"""Dabsky prompt-conditioning service.

This service wraps the official Hunyuan3D-1 text-to-image stage. It is kept
separate from the shape worker so each model can be placed on the right GPU
(or on separate hosts) without putting model weights in the Android app.
"""

from __future__ import annotations

import hmac
import json
import os
import sys
import threading
from io import BytesIO
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response

MAX_PROMPT_CHARS = 500
MAX_IMAGE_BYTES = 6 * 1024 * 1024
MAX_STEPS = 50


class ModelLicenseError(RuntimeError):
    """Generation is blocked until the model license has been reviewed."""


class HunyuanTextRuntime:
    def __init__(self) -> None:
        self.repo_path = Path(os.getenv("HUNYUAN1_REPO_PATH", "/opt/hunyuan3d1"))
        self.model_path = os.getenv(
            "HUNYUAN1_TEXT_MODEL_PATH",
            "/opt/hunyuan3d1/weights/hunyuanDiT",
        )
        self.device = os.getenv("DABSKY_MODEL_DEVICE", "cuda:0")
        self.save_memory = os.getenv("DABSKY_SAVE_MEMORY", "").lower() in {
            "1",
            "true",
            "yes",
        }
        self._model: Any | None = None
        self._lock = threading.Lock()

    def _check_license_gate(self) -> None:
        if os.getenv("DABSKY_HUNYUAN_LICENSE_ACK", "").strip() != "I_HAVE_REVIEWED_LICENSE":
            raise ModelLicenseError(
                "Hunyuan text conditioning is disabled until its license is reviewed."
            )

    def _load(self) -> Any:
        self._check_license_gate()
        if self._model is not None:
            return self._model
        with self._lock:
            if self._model is not None:
                return self._model
            if str(self.repo_path) not in sys.path:
                sys.path.insert(0, str(self.repo_path))
            try:
                from infer import Text2Image
            except ImportError as exc:
                raise RuntimeError(
                    "Hunyuan3D-1 is not installed. Build backend/text-conditioner/Dockerfile first."
                ) from exc
            self._model = Text2Image(
                pretrain=self.model_path,
                device=self.device,
                save_memory=self.save_memory,
            )
            return self._model

    def generate(self, prompt: str, seed: int, steps: int) -> tuple[bytes, str]:
        image = self._load()(prompt, seed=seed, steps=steps).convert("RGB")
        output = BytesIO()
        image.save(output, format="PNG", optimize=True)
        image_bytes = output.getvalue()
        mime_type = "image/png"
        if len(image_bytes) > MAX_IMAGE_BYTES:
            output = BytesIO()
            image.save(output, format="JPEG", quality=90, optimize=True)
            image_bytes = output.getvalue()
            mime_type = "image/jpeg"
        if len(image_bytes) > MAX_IMAGE_BYTES:
            raise RuntimeError("Conditioned image exceeds the 6 MB safety limit.")
        return image_bytes, mime_type


app = FastAPI(title="Dabsky text conditioner", version="1.0.0")
runtime = HunyuanTextRuntime()


def _authorized(request: Request) -> None:
    expected = os.getenv("DABSKY_TEXT_CONDITIONER_TOKEN", "").strip()
    allow_unauthenticated = os.getenv(
        "DABSKY_ALLOW_UNAUTHENTICATED", ""
    ).strip().lower() in {"1", "true", "yes"}
    if not expected:
        if allow_unauthenticated:
            return
        raise HTTPException(
            status_code=503,
            detail="Conditioner authentication is not configured.",
        )
    supplied = request.headers.get("authorization", "")
    if not supplied.startswith("Bearer ") or not hmac.compare_digest(
        supplied[7:], expected
    ):
        raise HTTPException(status_code=401, detail="Conditioner token required.")


@app.get("/health")
async def health(request: Request) -> JSONResponse:
    _authorized(request)
    acknowledged = (
        os.getenv("DABSKY_HUNYUAN_LICENSE_ACK", "").strip()
        == "I_HAVE_REVIEWED_LICENSE"
    )
    return JSONResponse(
        {
            "status": "ok",
            "service": "dabsky-text-conditioner",
            "version": "1.0.0",
            "model": "hunyuan3d-1-text2image",
            "device": runtime.device,
            "weights_present": Path(runtime.model_path).exists(),
            "ready_for_generation": acknowledged and Path(runtime.model_path).exists(),
        }
    )


@app.post("/generate")
async def generate(request: Request) -> Response:
    _authorized(request)
    try:
        body = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Expected a JSON object.") from exc
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Expected a JSON object.")

    prompt = body.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise HTTPException(status_code=400, detail="Prompt is required.")
    prompt = prompt.strip()
    if len(prompt) > MAX_PROMPT_CHARS:
        raise HTTPException(status_code=400, detail="Prompt is too long.")

    try:
        seed = int(body.get("seed", 0))
        steps = int(body.get("steps", 25))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Seed and steps must be integers.") from exc
    if seed < 0 or seed > 2**31 - 1:
        raise HTTPException(status_code=400, detail="Seed is out of range.")
    if steps < 1 or steps > MAX_STEPS:
        raise HTTPException(status_code=400, detail=f"Steps must be 1–{MAX_STEPS}.")

    try:
        image_bytes, mime_type = runtime.generate(prompt, seed, steps)
    except ModelLicenseError as exc:
        raise HTTPException(status_code=412, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Conditioning failed: {exc}") from exc
    return Response(
        content=image_bytes,
        media_type=mime_type,
        headers={"Cache-Control": "no-store", "X-Dabsky-Conditioner": "hunyuan3d-1"},
    )
