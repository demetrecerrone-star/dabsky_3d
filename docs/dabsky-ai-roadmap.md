# Dabsky AI – development path

## v0.6 Offline Modeling Assistant

The v0.6 assistant is a deterministic local natural-language command interpreter, not a trained model. It performs whitelisted modeling commands with existing Godot tools: primitives, positioning, rotations, scale, material colors and PBR values, selection, renaming, duplication, deletion, undo/redo, and saving. It does not contact a server or require an API key. Unknown requests fail visibly without changing the scene.

The interpreter in scripts/dabsky_ai.gd returns an array of validated command dictionaries. scripts/main.gd dispatches those commands to modeling functions. A later LLM should return the **same validated command format**, never arbitrary GDScript.

## Later release: online text-to-3D generation

Not present in v0.6. Connect to a secured backend rather than embedding Tripo, Meshy or other provider credentials in an Android app.

Proposed API:
- POST /v1/generation: authenticated user prompt, requested settings, explicit cost approval -> job ID.
- GET /v1/generation/{id}: authenticated job status, progress, errors.
- GET /v1/generation/{id}/model: authenticated short-lived GLB result, enforce size/mime limits.
- Server: per-user quotas, abuse protection, private provider keys, content checks and task cancellation.
- Client: explain model generation charges, show progress, download result and import using existing GLB path.

Generating complete game-ready models requires retopology/material/rigging refinement. Offline command support and online model generation must remain clearly labeled.
