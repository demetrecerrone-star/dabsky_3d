# Dabsky 3D Studio

Android-first Godot 4 3D modeling app with a local-first AI modeling partner.

## v0.7 Generation Studio

Dabsky can turn short prompts into editable multi-part assets without a provider key:

- stylized swords, staffs, bows, shields, trees, houses, chests, crystals, characters and props
- prompt colors and low-poly/stylized/detailed style hints
- every generated part remains individually selectable, transformable, material-editable and undoable
- existing GLB import/export, project save/load and offline modeling commands remain available

The generator returns a validated recipe schema. A future hosted model can produce the same schema without giving the Android client arbitrary code execution or provider credentials.

Run the Godot headless tests with the scripts in `tests/`.
