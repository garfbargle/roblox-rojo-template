# INTEGRATE — wire `modelsnap` into this Roblox game

**You are an AI integrating this kit into the current Roblox project.** Follow
these steps in order. Goal: render this game's procedural models to PNGs from the
CLI, so previews can be eyeballed without opening Studio. When you finish, ONE of
this game's models must render to a PNG you can show.

This folder (`modelsnap/`) is generic — never edit `render_core.py`,
`cli_shim_core.luau`, `snapshot.luau`, or `scaffold_module_tree.py`. You only
create two small per-game adapters from `templates/`.

## Prerequisites (check first)
- The repo is a **Rojo** project (look for `*.project.json`) and procedural
  models are built in **Luau** by builder modules (functions that construct and
  return a `Model` of `Part`s). If models are meshes/assets, not code-built
  parts, this kit does not apply — stop and say so.
- `luau` and `python3` are on PATH (`luau --help`, `python3 --version`).

## Step 1 — Place the folder
This folder should live at `tool/modelsnap/` in the repo root. If it's elsewhere,
move it there (or adjust the `modelsnap` alias path in Step 2 to match).

## Step 2 — Add `.luaurc` aliases
Ensure the repo-root `.luaurc` aliases both the source root and this kit. Find
the ReplicatedStorage source path from `*.project.json` (the `$path` mapped to
`ReplicatedStorage`, e.g. `src/ReplicatedStorage`). Create `.luaurc` if absent:
```jsonc
{ "aliases": {
    "ReplicatedStorage": "./src/ReplicatedStorage",
    "modelsnap": "./tool/modelsnap"
} }
```
If the game already uses a different alias name for its source, keep it and use
that name in Step 4's tree and Step 5's requires.

## Step 3 — Learn the builders
Read the builders directory (commonly `.../Builders/`). For ONE simple cosmetic
or prop builder, note: the module path, the function that returns a `Model`, and
its arguments. This is your smoke-test target in Step 5.

## Step 4 — Create the CLI shim adapter
Builders run under the CLI by gating on the shim:
`if game then nil else require("@ReplicatedStorage/Shared/RobloxCliShim")`.
Find that exact require path in the builders (grep `RobloxCliShim`) — that's where
the adapter must live (usually `src/ReplicatedStorage/Shared/RobloxCliShim.luau`).

1. Copy `templates/RobloxCliShim.luau` to that path.
2. Generate the module tree and paste it over the `BEGIN/END module tree` block:
   ```bash
   python3 tool/modelsnap/scaffold_module_tree.py   # reads .luaurc
   ```
3. Keep the `Players` rig only if a builder calls
   `CreateHumanoidModelFromDescription`; otherwise delete it and pass no `players`.

## Step 5 — Create the exporter
1. Copy `templates/export_model_snapshot.luau` to `tool/export_model_snapshot.luau`.
2. Add ONE entry to `TARGETS` for the builder from Step 3, e.g.:
   ```lua
   hat = function()
       local ItemPreview = need("Builders", "ItemPreview")
       local Items = need("Data", "Items")
       return ItemPreview.Build(Items.Resolve("SomeItemId")), "Some Item"
   end,
   ```

## Step 6 — Smoke test (definition of done)
```bash
luau tool/export_model_snapshot.luau -a --target hat > /tmp/snap.json
python3 tool/modelsnap/render_core.py --snapshot /tmp/snap.json --out output/preview.png
```
Open/show `output/preview.png`. If it shows the model, you're done. Add more
`TARGETS` entries as needed, and optionally copy this repo's
`tool/render_model_snapshot.py` as a one-command front-end.

## Gotchas (read if anything fails)
- **`attempt to call/index nil` during export** → the shim is a *partial*
  emulation; a builder used a Roblox API not yet stubbed. Add the stub:
  - an engine API (e.g. a new `Instance` class field, a math type) → `cli_shim_core.luau`;
  - a game module/service (e.g. `game:GetService("X")`, a missing tree entry) →
    your `RobloxCliShim.luau` adapter (regenerate the tree, or add a `services` entry).
  Re-run. Engine additions help every game.
- **`@modelsnap is not a valid alias`** → Step 2 alias missing/typo'd, or you're
  running from a directory whose `.luaurc` doesn't define it. Run from repo root.
- **A directory with `init.luau`** is a ModuleScript: the scaffolder emits it as a
  leaf `Name = "@.../Name"`, not a folder. That's correct — require it as a unit.
- **A model renders but looks wrong** — this renderer matches Roblox's real shape
  rules and has limits (see `README.md`): a `Cylinder` extrudes along local X
  (un-rotated = sideways slab); a `Ball` is a sphere of the smallest axis; there
  is no lighting/material/glow; runtime-set properties (post-build tweens, GUIs)
  are not applied. Terrain (carved walls) isn't a `BasePart` and isn't picked up
  automatically, but `render_core.py` can rasterise an optional heightfield
  ground layer if you hand it one — see README.md's "Terrain" section.
- **A room/landmark renders tiny or ambiguous** → use `--focus "x,y,z" --span N`
  to frame a subject inside a sprawling build, and a top-down plan view
  (`--yaw 0 --pitch 88`) to inspect interiors (no per-pixel z-buffer).
- **Don't commit** `tool/modelsnap/__pycache__/` — add `__pycache__/` to `.gitignore`.
