# Dabsky text conditioner

This service provides the prompt-only stage for Dabsky's Hunyuan3D worker.
It wraps the official Hunyuan3D-1 `Text2Image` pipeline and returns a
validated PNG/JPEG image to `backend/inference`.

## Build

```bash
docker build -t dabsky-text-conditioner backend/text-conditioner
```

Download the official Hunyuan3D-1 text model into a host directory, then mount
it into the container at `/opt/hunyuan3d1/weights/hunyuanDiT`. The Docker image
contains the code and dependencies, not model weights.

```bash
docker run --gpus all --rm -p 8090:8090 \
  -e DABSKY_TEXT_CONDITIONER_TOKEN='use-a-secret-token' \
  -e DABSKY_HUNYUAN_LICENSE_ACK='I_HAVE_REVIEWED_LICENSE' \
  -v /srv/dabsky/weights/hunyuanDiT:/opt/hunyuan3d1/weights/hunyuanDiT:ro \
  dabsky-text-conditioner
```

Set the Dabsky shape worker's `DABSKY_TEXT_TO_IMAGE_URL` to
`http://conditioner-host:8090/generate` and set
`DABSKY_TEXT_TO_IMAGE_TOKEN` to the same token.

Hunyuan3D-1 and its model weights are license-gated. Review the official
Tencent Hunyuan license and the licenses of its third-party dependencies before
using this service commercially. Do not place the token or model weights in the
APK.
