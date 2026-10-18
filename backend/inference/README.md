# Dabsky AI v1 GPU worker

This is the first real neural-generation worker for Dabsky. It wraps the official
Hunyuan3D-2.1 shape pipeline behind Dabsky's job API, so the Android app receives
an asynchronous, editable GLB instead of a procedural recipe.

The worker supports two prompt paths:

- **Reference image + prompt:** sent directly to Hunyuan3D-2.1.
- **Prompt only:** sent to a private text-to-image conditioner when
  `DABSKY_TEXT_TO_IMAGE_URL` is configured, then passed through the same
  Hunyuan3D shape pipeline.

The conditioner is intentionally an HTTP adapter, so Dabsky can use a local
text-to-image model or a private hosted model without putting its weights or
credentials in the APK. It must accept `POST {"prompt":"..."}` and return either
an image response or JSON with `image_base64` (optionally `mime_type`).

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
  -e DABSKY_TEXT_TO_IMAGE_URL='http://text-image-service:9000/generate' \
  -e DABSKY_TEXT_TO_IMAGE_TOKEN='text-image-secret' \
  dabsky-ai-worker
```

Keep the worker URL and worker token server-side. Set the Firebase Function
variables `DABSKY_INFERENCE_URL` and `DABSKY_INFERENCE_TOKEN`; the Android app
should continue using the Firebase Dabsky API URL, not the RunPod URL. This
keeps the GPU worker private and prevents the worker token from entering the
APK.

For direct worker testing, call `/health` and `/v1/catalog` with the worker
bearer token. Without `DABSKY_TEXT_TO_IMAGE_URL`, reference-image generation
still works and prompt-only requests return a clear configuration error. The
Android app keeps its offline prompt generator as the local fallback.

## Important licensing gate

The Hunyuan3D-2.1 repository states that Hunyuan 3D is licensed under the
Tencent Hunyuan Non-Commercial License Agreement. Review that license before
using this worker for Dabsky Creative Studio, paid features, or a public
commercial release. The worker refuses generation until the explicit
`DABSKY_HUNYUAN_LICENSE_ACK` environment variable is set.

This worker does not place model weights, tokens, or GPU credentials in the APK.
