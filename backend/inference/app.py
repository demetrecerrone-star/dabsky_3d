"""Dabsky AI v1 GPU worker.

This service turns a validated reference image into a GLB asynchronously. It is
deliberately separate from Firebase so GPU memory and model credentials never
enter the Android app or the low-cost API layer. Prompt-only jobs optionally use
a private text-to-image conditioner before entering the same shape pipeline.
"""

from __future__ import annotations

import hmac
import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, JSONResponse

from conditioning import ConditioningError, TextConditioner
from contract import PayloadError, decode_payload
from runtime import HunyuanRuntime, ModelLicenseError

RESULT_ROOT = Path(os.getenv("DABSKY_RESULT_DIR", "/tmp/dabsky-results"))
MAX_MODEL_BYTES = 80 * 1024 * 1024
executor = ThreadPoolExecutor(max_workers=max(1, int(os.getenv("DABSKY_WORKERS", "1"))))
runtime = HunyuanRuntime()
conditioner = TextConditioner()
jobs: dict[str, dict[str, Any]] = {}
jobs_lock = threading.Lock()

app = FastAPI(title="Dabsky AI v1 GPU worker", version="1.1.0")


def _authorized(request: Request) -> None:
    expected = os.getenv("DABSKY_WORKER_TOKEN", "").strip()
    if not expected:
        return
    supplied = request.headers.get("authorization", "")
    if not supplied.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Worker token required.")
    if not hmac.compare_digest(supplied[7:], expected):
        raise HTTPException(status_code=401, detail="Invalid worker token.")


def _snapshot(job_id: str) -> dict[str, Any]:
    with jobs_lock:
        job = dict(jobs[job_id])
    return {
        "id": job_id,
        "status": job["status"],
        "progress": job.get("progress", 0),
        "message": job.get("message", ""),
        "model_path": f"/v1/jobs/{job_id}/model"
        if job["status"] == "ready"
        else None,
    }


def _set_job(job_id: str, **values: Any) -> None:
    with jobs_lock:
        jobs[job_id].update(values)


def _is_cancelled(job_id: str) -> bool:
    with jobs_lock:
        job = jobs.get(job_id)
        return job is None or job.get("status") == "canceled" or bool(
            job.get("cancel_requested", False)
        )


def _write_reference(job_id: str, reference: dict[str, Any]) -> Path:
    suffix = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/webp": ".webp",
    }[reference["mime_type"]]
    job_dir = RESULT_ROOT / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    path = job_dir / f"reference{suffix}"
    path.write_bytes(reference["bytes"])
    return path


def _export_glb(mesh: Any, output_path: Path) -> None:
    mesh.export(str(output_path), file_type="glb")
    if not output_path.exists() or output_path.stat().st_size < 20:
        raise RuntimeError("Hunyuan returned an empty mesh.")
    if output_path.stat().st_size > MAX_MODEL_BYTES:
        raise RuntimeError("Generated GLB exceeds the 80 MB safety limit.")
    with output_path.open("rb") as stream:
        if stream.read(4) != b"glTF":
            raise RuntimeError("Generated output was not a valid GLB.")


def _run_generation(job_id: str, prompt: str, reference: dict[str, Any]) -> None:
    reference_path: Path | None = None
    output_path = RESULT_ROOT / job_id / "model.glb"
    try:
        reference_path = _write_reference(job_id, reference)
        if _is_cancelled(job_id):
            return
        _set_job(job_id, status="running", progress=8, message="Loading Dabsky AI model…")
        if _is_cancelled(job_id):
            return
        _set_job(job_id, progress=20, message="Reconstructing 3D shape…")
        mesh = runtime.generate_shape(reference_path)
        if _is_cancelled(job_id):
            output_path.unlink(missing_ok=True)
            return
        _set_job(job_id, progress=88, message="Validating game-ready GLB…")
        _export_glb(mesh, output_path)
        if _is_cancelled(job_id):
            output_path.unlink(missing_ok=True)
            return
        _set_job(job_id, status="ready", progress=100, message="Model ready.")
    except ModelLicenseError as exc:
        if not _is_cancelled(job_id):
            _set_job(job_id, status="failed", message=str(exc))
    except Exception as exc:
        if not _is_cancelled(job_id):
            _set_job(job_id, status="failed", message=f"Generation failed: {exc}")
    finally:
        if reference_path is not None:
            try:
                reference_path.unlink(missing_ok=True)
            except OSError:
                pass


@app.get("/health")
async def health(request: Request) -> JSONResponse:
    _authorized(request)
    return JSONResponse(
        {
            "status": "ok",
            "service": "dabsky-ai-worker",
            "version": "1.1.0",
            "model": runtime.model_path,
            "device": runtime.device,
            "ready_for_generation": os.getenv(
                "DABSKY_HUNYUAN_LICENSE_ACK", ""
            ).strip()
            == "I_HAVE_REVIEWED_LICENSE",
            "text_conditioning_available": conditioner.available(),
            "diagnostics": runtime.diagnostics(),
        }
    )


@app.get("/v1/catalog")
async def catalog(request: Request) -> JSONResponse:
    _authorized(request)
    return JSONResponse(
        {
            "generator": "hunyuan3d-2.1",
            "text_to_mesh_ai": conditioner.available(),
            "image_to_mesh_ai": True,
            "reference_images": True,
            "text_conditioning": (
                "private_text_to_image_endpoint"
                if conditioner.available()
                else "not_configured"
            ),
            "output_formats": ["glb"],
        }
    )


@app.post("/v1/jobs")
async def create_job(request: Request) -> JSONResponse:
    _authorized(request)
    try:
        payload = decode_payload(await request.json())
    except PayloadError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    reference = payload["reference"]
    if reference is None:
        try:
            reference = await run_in_threadpool(
                conditioner.image_for_prompt, payload["prompt"]
            )
        except ConditioningError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

    job_id = uuid.uuid4().hex
    with jobs_lock:
        jobs[job_id] = {
            "status": "queued",
            "progress": 0,
            "message": "Queued for Dabsky AI generation.",
            "prompt": payload["prompt"],
            "cancel_requested": False,
        }
    executor.submit(_run_generation, job_id, payload["prompt"], reference)
    return JSONResponse(_snapshot(job_id), status_code=202)


@app.post("/v1/jobs/{job_id}/cancel")
async def cancel_job(job_id: str, request: Request) -> JSONResponse:
    _authorized(request)
    with jobs_lock:
        if job_id not in jobs:
            raise HTTPException(status_code=404, detail="Job not found.")
        job = jobs[job_id]
        if job["status"] in {"ready", "failed", "canceled"}:
            return JSONResponse(_snapshot(job_id))
        job.update(
            status="canceled",
            message="Cancellation requested.",
            cancel_requested=True,
        )
    return JSONResponse(_snapshot(job_id))


@app.get("/v1/jobs/{job_id}")
async def get_job(job_id: str, request: Request) -> JSONResponse:
    _authorized(request)
    with jobs_lock:
        if job_id not in jobs:
            raise HTTPException(status_code=404, detail="Job not found.")
    return JSONResponse(_snapshot(job_id))


@app.get("/v1/jobs/{job_id}/model")
async def get_model(job_id: str, request: Request) -> FileResponse:
    _authorized(request)
    with jobs_lock:
        job = jobs.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found.")
    if job["status"] != "ready":
        raise HTTPException(status_code=409, detail="Model is not ready.")
    path = RESULT_ROOT / job_id / "model.glb"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Generated model is unavailable.")
    return FileResponse(
        path,
        media_type="model/gltf-binary",
        filename=f"dabsky-{job_id}.glb",
    )
