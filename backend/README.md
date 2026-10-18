# Dabsky Connect backend

Firebase Project ID: `dabsky-3d`.

The backend now has two generation modes:

1. **Dabsky AI v1 worker mode** — when `DABSKY_INFERENCE_URL` is configured, authenticated jobs are forwarded to the GPU worker in `backend/inference`. The worker runs Hunyuan3D-2.1 image-to-shape generation and returns an asynchronous GLB job.
2. **Procedural fallback mode** — when no worker URL is configured, the tested barrel/chest/table generator remains available.

## API

- `GET /health`: public service status and whether the neural worker is configured.
- `GET /v1/catalog`: capabilities.
- `POST /v1/jobs`: Firebase Auth bearer token plus prompt and optional reference image.
- `GET /v1/jobs/{id}`: owner-only status and progress.
- `GET /v1/jobs/{id}/model`: owner-only GLB download.

Reference images are validated, forwarded to the private worker in memory, and reduced to metadata in Firestore. Uploaded image bytes are not stored in job documents.

## Connecting the GPU worker

Deploy `backend/inference` on a GPU host with the NVIDIA Container Toolkit. Set these Firebase Function environment variables:

- `DABSKY_INFERENCE_URL`: private or authenticated worker URL.
- `DABSKY_INFERENCE_TOKEN`: worker bearer token.

The worker currently requires a reference image. Prompt-only text-to-image conditioning is the next model stage; until then, the Android app's offline prompt generator remains the prompt-only fallback.

## Security and limits

- Firebase ID tokens are verified with Admin SDK, including token revocation.
- Each job belongs to one user; cross-user access returns 404.
- Quota limit: 20 new jobs per UID per UTC day.
- API payloads cap reference images at 6 MB.
- No service-account key, model weights, worker token, or GPU credential is placed in the Android APK.
- Cloud Functions deployment requires Firebase Blaze billing. Do not enable paid deployment without approving possible charges.

## Licensing

The Hunyuan3D-2.1 repository states that Hunyuan 3D is under the Tencent Hunyuan Non-Commercial License Agreement. Review that license before using the worker for paid Dabsky Creative Studio features or a public commercial release. The worker includes an explicit license acknowledgement gate.

Run the backend and worker contract tests with:

```bash
npm test --prefix backend/functions
python -m unittest discover -s backend/inference -p "test_*.py"
```

No model weights or service-account keys are committed to this repository.
