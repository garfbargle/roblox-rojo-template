# modelsnap — portable Roblox procedural-model previewer

Render procedural Roblox models (built in Luau) to PNGs **outside Studio**, from
the CLI. Drop this folder into any Rojo-based Roblox game. It is engine-generic;
the only per-game code is a short shim adapter and an exporter that knows your
builders.

> Provisional home of the "Garfbargle Standard Library". Extract to its own repo
> and pull in as a submodule when you have more than one game using it.

## Integrating into a new game

Copy this whole folder into the new repo, then point an AI (or yourself) at
**[`INTEGRATE.md`](INTEGRATE.md)** — a step-by-step runbook that wires it up
using the ready-to-fill `templates/`. The manual summary is under
"Drop into a new game" below.

## What's in here (all generic — copy as-is)

| File | Role |
|---|---|
| `INTEGRATE.md` | Step-by-step runbook for an AI/dev to wire the kit into a new game. |
| `render_core.py` | The renderer. Snapshot JSON → PNG. No deps beyond Python 3 stdlib, no game knowledge. Run standalone (`--snapshot`) or import `render(...)`. |
| `cli_shim_core.luau` | Engine-level Roblox API stubs (Vector3/CFrame/Color3/Enum/Instance/…) so builders run under the `luau` CLI. Exposes `Compose{...}`. |
| `snapshot.luau` | Walks a built `Model` → the snapshot table; `Encode` → JSON. |
| `scaffold_module_tree.py` | Prints the fake-ReplicatedStorage tree to paste into your shim adapter. |
| `templates/` | Copy-and-fill per-game adapters: `RobloxCliShim.luau` (shim) and `export_model_snapshot.luau` (exporter). |

## The contract: the snapshot JSON

`render_core.py` only knows this shape — anything that emits it (this CLI, a
Studio plugin, another language) can drive the renderer:

```jsonc
{
  "label": "Reelrunner's Lucky Hat",   // shown in the CLI summary line
  "source": "item:ReelrunnersLuckyHat",
  "partCount": 30,
  "parts": [
    {
      "name": "LuckyHatWideBrim",
      "className": "Part",              // Part | WedgePart | MeshPart
      "shape": "PartType.Cylinder",     // matched by substring: Ball / Cylinder / Wedge / else Block
      "material": "Material.Wood",      // "Neon" gets a glow tint; otherwise cosmetic
      "size": { "x": 3.24, "y": 0.13, "z": 2.5 },
      "cframe": {
        "position": { "x": 0, "y": 1.1, "z": 0 },
        "rotation": [[1,0,0],[0,1,0],[0,0,1]]   // 3x3 row-major
      },
      "color": { "r": 178, "g": 126, "b": 55 }, // 0–255
      "transparency": 0                          // ≥0.98 is dropped
    }
  ]
}
```

The renderer mirrors Roblox's real part-shape rules so previews predict the live
game: a **Cylinder** extrudes along local **X** (an un-rotated cylinder is a
sideways slab, not a flat disc); a **Ball** is a sphere of the **smallest** Size
axis (non-uniform Size is not an ellipsoid). It does **not** model lighting,
materials, neon glow, lights, or particles.

## Drop into a new game

1. **Copy** `tool/modelsnap/` into the new repo.
2. **Add aliases** in `.luaurc` (both the engine kit and your source root):
   ```jsonc
   { "aliases": {
       "ReplicatedStorage": "./src/ReplicatedStorage",
       "modelsnap": "./tool/modelsnap"
   } }
   ```
3. **Write the shim adapter** at the path your builders import (they use
   `if game then nil else require("@ReplicatedStorage/Shared/RobloxCliShim")`).
   It declares the module tree + an optional character rig, then composes:
   ```lua
   local Core = require("@modelsnap/cli_shim_core")
   local folder = Core.folder
   -- paste the output of scaffold_module_tree.py here:
   local ReplicatedStorage = folder({ --[[ Shared = folder{...}, ... ]] })
   return Core.Compose({ replicatedStorage = ReplicatedStorage --[[, players = ... ]] })
   ```
   Generate the tree:
   `python3 tool/modelsnap/scaffold_module_tree.py` (reads `.luaurc`).
4. **Write the exporter** `tool/export_model_snapshot.luau` — require your
   builders + `@modelsnap/snapshot`, turn CLI args into a `Model`, then
   `print(Snapshot.Encode(Snapshot.FromModel(model, label, source)))`.
5. **Render**:
   ```bash
   luau tool/export_model_snapshot.luau -a --item Foo > /tmp/foo.json
   python3 tool/modelsnap/render_core.py --snapshot /tmp/foo.json --out out.png
   ```
   (Optionally add a thin `render_model_snapshot.py` front-end that does both in
   one command — see this repo's copy for a template.)

## Extending the shim

The shim stubs only the APIs builders happen to call. The first time a builder
hits an un-stubbed one it fails loudly (`attempt to call/index nil`). Add the
stub to `cli_shim_core.luau` (engine API) or your shim adapter (a game module /
service) — engine additions help every game.

### Engine additions log

Real engine behavior added to `cli_shim_core.luau` over time (vs. the original
minimal stubs). If you extract this kit upstream, keep these:

- **`CFrame.lookAt(eye, target, up)`** — now a real implementation: `LookVector`
  (−Z) points from `eye` toward `target`, matching Roblox. (Was a no-op that
  returned identity rotation, which silently left any `lookAt`-oriented part
  unrotated — wrong previews for every builder that orients via `lookAt`.)
- **`Vector3.xAxis` / `Vector3.yAxis` / `Vector3.zAxis`** — the standard axis
  constants (commonly passed as the `up` vector to `CFrame.lookAt`).

## Camera flags (render_core.py)

`--out --width --height --yaw --pitch --padding --focus "x,y,z" --span N`

- Big/embedded build framed tiny? Auto-fit includes far-flung approach parts —
  use `--focus`/`--span` to frame just the subject.
- Occlusion is resolved by a **per-pixel z-buffer** (each part's camera-facing
  surface is ray-cast per pixel), so nested, interpenetrating, or wildly
  different-sized parts hide each other correctly — a part is never drawn on top
  just because its centre happens to be nearer.
- Inspecting a room interior? A **top-down plan view** (`--yaw 0 --pitch 88`) is
  still the clearest way to read packed furniture.
- The CLI captures **build-time** state; properties set by runtime code (gate
  transparency toggles, GUIs, dynamic lights) won't show.

## Terrain (optional ground layer)

Terrain (carved walls/ceilings) is not `BasePart`s, so it never appears from the
part snapshot alone. `render()`/`--terrain` accept a separate heightfield
contract that's triangulated and rasterised through the **same** z-buffer as
parts, so a structure on a hillside occludes/is-occluded-by the ground
correctly instead of floating over a flat plane:

```jsonc
"terrain": {
  "originX": -50, "originZ": -50, "cellSize": 4,   // grid origin + spacing,
  "rows": 26, "cols": 26,                          // same coordinate space the parts use
  "heights": [[y, y, ...], ...],                   // rows x cols, row-major (Z, X)
  "colors":  [[{"r":,"g":,"b":}, ...], ...]        // optional per-vertex; flat green if omitted
}
```

Pass it as `snapshot["terrain"]`, or standalone via `render_core.py --snapshot
model.json --terrain terrain.json`. Lighting is one fixed fake directional
light (no real lighting model) so slopes read as slopes. This repo's
`export_terrain_snapshot.luau` + `render_model_snapshot.py --with-terrain
--terrain-at "x,z"` sample the real `Shared/Heightmap` and recentre the result
to the model's local coordinate space — see that script's header before
copying the pattern into a new game (most builders here build at local
`(0,0,0)`, not their true world placement, so "where to sample" and "where the
camera looks" are deliberately separate flags).
