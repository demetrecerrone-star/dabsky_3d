"""Lazy Hunyuan3D-2.1 runtime.

The heavyweight model is imported only when the first generation arrives. This keeps
health checks and contract tests usable without CUDA or model weights.
"""

from __future__ import annotations

import os
import sys
from importlib.util import find_spec
from pathlib import Path
from typing import Any


class ModelLicenseError(RuntimeError):
    """Generation is blocked until the model license has been reviewed."""


class HunyuanRuntime:
    def __init__(self) -> None:
        self.repo_path = Path(os.getenv("HUNYUAN_REPO_PATH", "/opt/hunyuan3d"))
        self.model_path = os.getenv("HUNYUAN_MODEL_PATH", "tencent/Hunyuan3D-2.1")
        self.shape_subfolder = os.getenv("HUNYUAN_SHAPE_SUBFOLDER", "hunyuan3d-dit-v2-1")
        self.device = os.getenv("DABSKY_MODEL_DEVICE", "cuda")
        self._shape_pipeline: Any | None = None

    def diagnostics(self) -> dict[str, Any]:
        """Return lightweight setup diagnostics without loading model weights."""
        license_acknowledged = (
            os.getenv("DABSKY_HUNYUAN_LICENSE_ACK", "").strip()
            == "I_HAVE_REVIEWED_LICENSE"
        )
        repo_exists = self.repo_path.exists()
        shape_package_available = False
        if repo_exists:
            try:
                shape_package_available = (
                    find_spec("hy3dshape", [str(self.repo_path)])
                    is not None
                )
            except (ImportError, ModuleNotFoundError, ValueError, AttributeError):
                shape_package_available = False
        return {
            "license_acknowledged": license_acknowledged,
            "repo_path_exists": repo_exists,
            "shape_package_available": shape_package_available,
            "model_loaded": self._shape_pipeline is not None,
        }

    def readiness(self) -> dict[str, Any]:
        """Return diagnostics plus the conditions required before generation."""
        diagnostics = self.diagnostics()
        diagnostics["ready_for_generation"] = bool(
            diagnostics["license_acknowledged"]
            and diagnostics["repo_path_exists"]
            and diagnostics["shape_package_available"]
        )
        return diagnostics

    def _check_license_gate(self) -> None:
        acknowledgement = os.getenv("DABSKY_HUNYUAN_LICENSE_ACK", "").strip()
        if acknowledgement != "I_HAVE_REVIEWED_LICENSE":
            raise ModelLicenseError(
                "Hunyuan generation is disabled until its license is reviewed. "
                "Set DABSKY_HUNYUAN_LICENSE_ACK only after approval."
            )

    def _load_shape_pipeline(self) -> Any:
        self._check_license_gate()
        if self._shape_pipeline is not None:
            return self._shape_pipeline
        if str(self.repo_path) not in sys.path:
            sys.path.insert(0, str(self.repo_path))
        try:
            from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
        except ImportError as exc:
            raise RuntimeError(
                "Hunyuan3D is not installed. Build backend/inference/Dockerfile first."
            ) from exc

        kwargs: dict[str, Any] = {}
        if self.shape_subfolder:
            kwargs["subfolder"] = self.shape_subfolder
        pipeline = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
            self.model_path, **kwargs
        )
        if hasattr(pipeline, "to"):
            pipeline = pipeline.to(self.device)
        self._shape_pipeline = pipeline
        return pipeline

    def generate_shape(self, image_path: Path) -> Any:
        pipeline = self._load_shape_pipeline()
        # Hunyuan's official API accepts an image path and returns a trimesh object.
        return pipeline(image=str(image_path))[0]
