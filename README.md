# Roblox Rojo Template

This is a boilerplate template repository for scaffolding new Roblox projects using [Rojo](https://rojo.space/). It includes a minimal structured architecture with a core generic `Loader` for modular client and server code, along with linting and code formatting pre-configured.

## Project Structure
- `src/ReplicatedStorage/` - Contains shared utilities and cross-boundary Types.
- `src/ServerScriptService/Services/` - Place your localized server-sided logics here.
- `src/StarterPlayerScripts/Controllers/` - Place your localized client-sided UI and interaction controllers here.
- `OptionalLibraries/` and `OtherScripts/` - Utility packs available for direct drop-in usage.

## Setup
The project relies on `aftman` as the toolchain manager. To get started:
1. `aftman install`
2. `rojo serve`
3. Connect using the Rojo plugin within Roblox Studio.

## Procedural Model Previews

For procedural parts-based models, use [modelsnap](tool/modelsnap/) to export and render snapshots from the CLI without opening Roblox Studio. This makes it easier to catch placement, rotation, shape, front/back orientation, and visibility issues while iterating on Luau builders.

Before building or changing procedural models, read the [Procedural Model Building Guide](Documentation/Procedural_Model_Building_Guide.md). It documents Roblox shape rules, z-fighting checks, local-coordinate assembly patterns, rig topology, and the render-and-review workflow that keeps generated models predictable.

### modelsnap usage

1. Add repo-root `.luaurc` aliases for the source tree and modelsnap:
   ```jsonc
   {
     "aliases": {
       "ReplicatedStorage": "./src/ReplicatedStorage",
       "modelsnap": "./tool/modelsnap"
     }
   }
   ```
2. Follow [tool/modelsnap/INTEGRATE.md](tool/modelsnap/INTEGRATE.md) to create the per-game CLI shim and `tool/export_model_snapshot.luau` target list.
3. Export a snapshot and render it:
   ```bash
   luau tool/export_model_snapshot.luau -a --target NAME > /tmp/model.json
   python3 tool/modelsnap/render_core.py --snapshot /tmp/model.json --out output/model.png
   ```

For an unrotated Roblox model, the front side is `-Z`. Use `--yaw 180` to inspect the front and `--yaw 0` to inspect the back:

```bash
python3 tool/modelsnap/render_core.py --snapshot /tmp/model.json --out output/front.png --yaw 180
python3 tool/modelsnap/render_core.py --snapshot /tmp/model.json --out output/back.png --yaw 0
```

For packed interiors or layout checks, a top-down render is often clearer:

```bash
python3 tool/modelsnap/render_core.py --snapshot /tmp/model.json --out output/top.png --yaw 0 --pitch 88
```
