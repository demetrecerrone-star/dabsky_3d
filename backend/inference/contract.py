"""Pure request validation shared by the Dabsky GPU worker and its tests."""

from __future__ import annotations

import base64
import binascii
from typing import Any

MAX_PROMPT_CHARS = 500
MAX_REFERENCE_BYTES = 6 * 1024 * 1024
SUPPORTED_MIME_TYPES = {"image/png", "image/jpeg", "image/webp"}


class PayloadError(ValueError):
    """A client-safe request validation error."""


def decode_payload(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise PayloadError("Expected a JSON object.")

    allowed = {
        "prompt",
        "output_format",
        "client",
        "client_version",
        "reference_image",
    }
    unsupported = set(payload) - allowed
    if unsupported:
        raise PayloadError("Unsupported request field.")

    prompt = payload.get("prompt")
    if not isinstance(prompt, str):
        raise PayloadError("Prompt is required.")
    prompt = prompt.strip()
    if not prompt or len(prompt) > MAX_PROMPT_CHARS:
        raise PayloadError(f"Prompt must contain 1–{MAX_PROMPT_CHARS} characters.")

    reference = payload.get("reference_image")
    decoded_reference: dict[str, Any] | None = None
    if reference is not None:
        if not isinstance(reference, dict):
            raise PayloadError("Reference image must be an object.")
        mime_type = reference.get("mime_type")
        if mime_type not in SUPPORTED_MIME_TYPES:
            raise PayloadError("Reference image must be PNG, JPEG or WebP.")
        encoded = reference.get("data_base64")
        if not isinstance(encoded, str) or not encoded:
            raise PayloadError("Reference image data is required.")
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error) as exc:
            raise PayloadError("Reference image encoding is invalid.") from exc
        if not raw or len(raw) > MAX_REFERENCE_BYTES:
            raise PayloadError("Reference image must be 1 byte to 6 MB.")
        decoded_reference = {
            "bytes": raw,
            "mime_type": mime_type,
            "filename": str(reference.get("filename", "reference-image"))[:96],
        }

    return {
        "prompt": prompt,
        "reference": decoded_reference,
        "output_format": payload.get("output_format", "glb"),
    }
