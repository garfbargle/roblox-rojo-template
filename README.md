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
