# Dabsky 3D Studio

Android-first Godot 4 3D modeling app with a local-first AI modeling partner.

## v0.8 Generation Studio

Dabsky can turn short prompts into editable multi-part assets without a provider key:

- stylized swords, staffs, bows, shields, trees, houses, chests, crystals, characters and props
- prompt colors and low-poly/stylized/detailed style hints
- every generated part remains individually selectable, transformable, material-editable and undoable
- existing GLB import/export, project save/load and offline modeling commands remain available

The v0.8 AI panel adds a provider-neutral remote generation path:

- configurable API endpoint with an optional Firebase ID token field that is never persisted
- PNG/JPG/JPEG/WebP reference-image selection with a 6 MB client-side cap
- visible upload/generation/download progress, cancel, retry and connection check states
- remote GLB results import through the same editable scene, undo and export pipeline
- local generation remains available when the network or backend is unavailable

The included backend scaffold accepts the prompt/reference contract and safely records only reference metadata. Its current output is an original procedural fallback, not a trained neural model. A trained Dabsky inference service can be connected behind the same API without putting provider credentials in the APK.

Run the Godot headless tests with the scripts in `tests/`.
