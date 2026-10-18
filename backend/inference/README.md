# Dabsky AI v1 GPU worker

This is the first real neural-generation worker for Dabsky. It wraps the official
Hunyuan3D-2.1 shape pipeline behind Dabsky's job API, so the Android app receives
an asynchronous, editable GLB instead of a procedural recipe.

The first stage is intentionally image-to-3D. Hunyuan3D-2.1's official pipeline
accepts a reference image and returns a mesh; prompt-only generation will use a
Dabsky text-to-image conditioning stage in a later milestone. The Android app
continues to use its offline generator when no reference image is available.

## Hardware

The official Hunyuan3D-2.1 project reports roughly 10 GB VRAM for shape
generation, 21 GB for texture generation, and 29 GB for both together. Start
with a GPU worker using shape-only mode, then enable textures after the
generation path is stable.

## Run with Docker

Build on a machine with an NVIDIA GPU and the NVIDIA Container Toolkit:

```bash
docker build -t dabsky-ai-worker backend/inference
docker run --gpus all --rm -p 8080:8080 \
  -e DABSKY_WORKER_TOKEN='use-a-secret-token' \
  -e DABSKY_HUNYUAN_LICENSE_ACK='I_HAVE_REVIEWED_LICENSE' \
  dabsky-ai-worker
```

Configure Dabsky's Remote AI API field to the worker URL. If a token is set,
put the same bearer token in the app's optional token field.

## Important licensing gate

The Hunyuan3D-2.1 repository states that Hunyuan 3D is licensed under the
Tencent Hunyuan Non-Commercial License Agreement. Review that license before
using this worker for Dabsky Creative Studio, paid features, or a public
commercial release. The worker refuses generation until the explicit
`DABSKY_HUNYUAN_LICENSE_ACK` environment variable is set.

This worker does not place model weights, tokens, or GPU credentials in the APK.
