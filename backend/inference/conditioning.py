"""Optional text-to-image conditioning for prompt-only Dabsky jobs.

The GPU worker stays model-provider neutral here: a local or private text-to-image
service can return a reference image, which is then sent through the same
Hunyuan3D image-to-shape path used by reference-image jobs.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
import urllib.error
import urllib.request
from typing import Any

from contract import PayloadError, decode_payload


class ConditioningError(RuntimeError):
    """A client-safe prompt-conditioning error."""


class TextConditioner:
    """Turn a prompt into a validated reference image when configured."""

    def __init__(
        self,
        url: str | None = None,
        token: str | None = None,
        timeout: float | None = None,
    ) -> None:
        configured_url = url if url is not None else os.getenv("DABSKY_TEXT_TO_IMAGE_URL", "")
        self.url = configured_url.strip().rstrip("/")
        self.token = (
            token if token is not None else os.getenv("DABSKY_TEXT_TO_IMAGE_TOKEN", "")
        ).strip()
        self.timeout = timeout or float(os.getenv("DABSKY_TEXT_TO_IMAGE_TIMEOUT", "120"))

    def available(self) -> bool:
        return bool(self.url)

    def image_for_prompt(self, prompt: str) -> dict[str, Any]:
        if not self.url:
            raise ConditioningError(
                "Prompt-only generation is not configured on this worker. "
                "Set DABSKY_TEXT_TO_IMAGE_URL to a private text-to-image endpoint."
            )

        headers = {"Accept": "application/json, image/*", "Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = urllib.request.Request(
            self.url,
            data=json.dumps({"prompt": prompt}).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                content_type = response.headers.get("Content-Type", "").split(";", 1)[0].lower()
                raw = response.read(6 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as exc:
            raise ConditioningError(
                f"Text-to-image endpoint rejected the prompt ({exc.code})."
            ) from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise ConditioningError("Text-to-image endpoint is unavailable.") from exc

        if len(raw) > 6 * 1024 * 1024:
            raise ConditioningError("Text-to-image endpoint returned an image larger than 6 MB.")

        if content_type.startswith("image/"):
            return self._validate_image(prompt, raw, content_type)

        try:
            result = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ConditioningError(
                "Text-to-image endpoint must return an image or JSON image_base64."
            ) from exc
        if not isinstance(result, dict):
            raise ConditioningError("Text-to-image endpoint returned an invalid response.")

        encoded = result.get("image_base64") or result.get("data_base64")
        if not isinstance(encoded, str) or not encoded:
            raise ConditioningError("Text-to-image endpoint returned no image.")

        mime_type = str(result.get("mime_type") or "image/png").split(";", 1)[0].lower()
        if encoded.startswith("data:") and "," in encoded:
            header, encoded = encoded.split(",", 1)
            mime_type = header[5:].split(";", 1)[0].lower() or mime_type
        try:
            image_bytes = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error) as exc:
            raise ConditioningError("Text-to-image endpoint returned invalid image data.") from exc
        return self._validate_image(prompt, image_bytes, mime_type)

    @staticmethod
    def _validate_image(prompt: str, image_bytes: bytes, mime_type: str) -> dict[str, Any]:
        try:
            return decode_payload(
                {
                    "prompt": prompt,
                    "reference_image": {
                        "filename": "prompt-condition",
                        "mime_type": mime_type,
                        "data_base64": base64.b64encode(image_bytes).decode("ascii"),
                    },
                }
            )["reference"]
        except PayloadError as exc:
            raise ConditioningError(str(exc)) from exc
