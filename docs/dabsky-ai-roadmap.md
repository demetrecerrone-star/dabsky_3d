# Dabsky AI – development path

## v0.6 Offline Modeling Assistant

The v0.6 assistant is a deterministic local natural-language command interpreter, not a trained model. It performs whitelisted modeling commands with existing Godot tools: primitives, positioning, rotations, scale, material colors and PBR values, selection, renaming, duplication, deletion, undo/redo, and saving. It does not contact a server or require an API key. Unknown requests fail visibly without changing the scene.

The interpreter in scripts/dabsky_ai.gd returns an array of validated command dictionaries. scripts/main.gd dispatches those commands to modeling functions. A later LLM should return the same validated command format, never arbitrary GDScript.

## v0.7 Local-first Generation Studio

The generator in scripts/dabsky_generator.gd turns a short prompt into a validated recipe of ordinary editable parts. It currently covers weapons, shields, trees, houses, chests, crystals, characters and general props. Each part is created as a normal MeshInstance3D with a name, primitive shape, transform, color, metallic value and roughness value.

This gives Dabsky a useful no-key generation path on Android immediately:

- results are inspectable and editable instead of opaque downloads
- generation is one undoable operation
- generated parts use the existing GLB export path
- prompt-to-recipe is deterministic and testable
- future AI services can return the same safe recipe schema without sending executable code to the client

This is intentionally a blockout/prototyping generator, not a claim of photorealistic neural reconstruction. The next quality step is to add a hosted or local inference adapter that returns the same recipe contract, followed by mesh cleanup, UV/material generation, rigging and validation.

## v0.8 Remote generation adapter

The v0.8 client in scripts/dabsky_remote.gd provides a safe provider-neutral request contract. The AI panel now supports:

- API health checks against a configurable endpoint
- prompt plus PNG/JPG/JPEG/WebP reference-image uploads capped at 6 MB
- optional bearer token input kept in memory only
- queued job polling, timeout handling, local cancel, retry and visible status
- GLB download and import through the existing editable scene path

The v0.8 Firebase scaffold accepts the request contract and stores only reference metadata, never the uploaded image bytes. Its current generator is still the deterministic procedural fallback. This is deliberate: it makes the client/backend seam testable without claiming that a hosted neural model already exists. The live Cloud Functions deployment remains a separate billing-gated step.

## Later release: online or local neural generation

Connect a secured backend or local inference worker rather than embedding provider credentials in an Android app.

Proposed API:
- POST /v1/generation: authenticated prompt, references, requested settings, explicit cost approval -> job ID.
- GET /v1/generation/{id}: authenticated job status, progress, errors.
- GET /v1/generation/{id}/model: authenticated short-lived GLB result, enforce size/mime limits.
- Server: per-user quotas, abuse protection, private provider keys, content checks and task cancellation.
- Client: show the generation mode, explain any cost, show progress, download result and import through the existing GLB path.

Dabsky's product advantage should be the complete loop: generate, inspect, edit, repair, material-edit, rig/animate and export to the user's game format in one place.
