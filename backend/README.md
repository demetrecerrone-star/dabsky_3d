# Dabsky Connect backend

Firebase Project ID: `dabsky-3d`.

The backend now has two generation modes:

1. **Dabsky AI v1 worker mode** — when `DABSKY_INFERENCE_URL` is configured,
   authenticated jobs are forwarded to the GPU worker in
   `backend/inference`. The worker runs Hunyuan3D-2.1 image-to-shape generation
   and returns an asynchronous GLB job.
2. **Procedural fallback mode** — when no worker URL is configured, the tested
   barrel/chest/table generator remains available.

## API

- `GET /health`: public service status, worker reachability, and readiness diagnostics.
- `GET /v1/catalog`: capabilities.
- `POST /v1/jobs`: Firebase Auth bearer token plus prompt and optional reference image.
- `GET /v1/jobs/{id}`: owner-only status and progress.
- `POST /v1/jobs/{id}/cancel`: owner-only cancellation request.
- `GET /v1/jobs/{id}/model`: owner-only GLB download.

Reference images are validated, forwarded to the private worker in memory, and
reduced to metadata in Firestore. Uploaded image bytes are not stored in job
documents.

## End-to-end GPU deployment

Dabsky's prompt-only path uses two services:

1. `backend/text-conditioner` runs Hunyuan3D-1 text-to-image.
2. `backend/inference` runs Hunyuan3D-2.1 image-to-shape and GLB export.

Put them on separate GPU hosts when possible. Both models can be large, and
keeping both resident on one GPU can cause out-of-memory failures. The
reference-image path only needs the shape worker.

Build the prompt conditioner:

```bash
docker build -t dabsky-text-conditioner backend/text-conditioner
docker run --gpus all --rm -p 8090:8090 \
  -e DABSKY_TEXT_CONDITIONER_TOKEN='conditioner-secret' \
  -e DABSKY_HUNYUAN_LICENSE_ACK='I_HAVE_REVIEWED_LICENSE' \
  -v /srv/dabsky/weights/hunyuanDiT:/opt/hunyuan3d1/weights/hunyuanDiT:ro \
  dabsky-text-conditioner
```

Build the shape worker:

```bash
docker build -t dabsky-ai-worker backend/inference
docker run --gpus all --rm -p 8080:8080 \
  -e DABSKY_WORKER_TOKEN='worker-secret' \
  -e DABSKY_HUNYUAN_LICENSE_ACK='I_HAVE_REVIEWED_LICENSE' \
  -e DABSKY_TEXT_TO_IMAGE_URL='http://conditioner-host:8090/generate' \
  -e DABSKY_TEXT_TO_IMAGE_TOKEN='conditioner-secret' \
  dabsky-ai-worker
```

Then set these Firebase Function environment variables:

- `DABSKY_INFERENCE_URL`: private or authenticated shape-worker URL.
- `DABSKY_INFERENCE_TOKEN`: shape-worker bearer token.

The Android app continues using the Firebase Dabsky API URL. Do not put the
RunPod URL or worker token in the APK.

Check both services before connecting the Android app:

```bash
curl http://conditioner-host:8090/health
curl http://worker-host:8080/health
curl http://worker-host:8080/v1/catalog
```

The worker accepts prompt-only jobs when its conditioner is configured. Without
the conditioner, reference-image generation remains available and the Android
app's offline prompt generator remains the prompt-only fallback.

## Security and limits

- Firebase ID tokens are verified with Admin SDK, including token revocation.
- Each job belongs to one user; cross-user access returns 404.
- Quota limit: 20 new jobs per UID per UTC day.
- API payloads cap reference images at 6 MB.
- No service-account key, model weights, worker token, or GPU credential is placed in the Android APK.
- Cloud Functions deployment requires Firebase Blaze billing. Do not enable paid deployment without approving possible charges.

## Licensing

Hunyuan3D-1 and Hunyuan3D-2.1 are license-gated. Review the official Tencent
Hunyuan license and third-party dependency licenses before using either service
for paid Dabsky Creative Studio features or a public commercial release. Both
services require the explicit `DABSKY_HUNYUAN_LICENSE_ACK` acknowledgement.

Run the backend and worker contract tests with:

```bash
npm test --prefix backend/functions
python -m unittest discover -s backend/inference -p "test_*.py"
python -m py_compile backend/text-conditioner/app.py
```

No model weights or service-account keys are committed to this repository.
