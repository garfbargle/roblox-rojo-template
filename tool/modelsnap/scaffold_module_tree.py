#!/usr/bin/env python3
"""Scaffold the fake ReplicatedStorage module tree for a game's CLI shim adapter.

The CLI shim can't list directories from inside the luau sandbox, so the module
tree (which modules exist where) is a hand-mirror of your source folders. This
script walks the source directory and prints the `local <Alias> = folder({...})`
block to paste into your per-game RobloxCliShim adapter — so you don't maintain
it by hand, and adding a module is a re-run instead of a silent "module missing".

Convention (matches Rojo): a directory containing init.luau IS a ModuleScript,
so it's emitted as a leaf alias; a directory without init.luau is a folder whose
children are emitted recursively; a `.luau`/`.lua` file is a leaf alias.

Usage (run from repo root):
  python3 tool/modelsnap/scaffold_module_tree.py            # reads .luaurc
  python3 tool/modelsnap/scaffold_module_tree.py --root ./src/ReplicatedStorage --alias ReplicatedStorage
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def alias_from_luaurc(luaurc: Path, alias: str) -> Path | None:
    if not luaurc.exists():
        return None
    data = json.loads(luaurc.read_text())
    rel = data.get("aliases", {}).get(alias)
    return (luaurc.parent / rel).resolve() if rel else None


def is_module_dir(d: Path) -> bool:
    return (d / "init.luau").exists() or (d / "init.lua").exists()


def module_name(path: Path) -> str:
    return path.stem  # drops .luau/.lua


def build(node: Path, alias: str, rel: str, indent: int) -> str:
    pad = "\t" * indent
    inner = "\t" * (indent + 1)
    entries: list[tuple[str, str]] = []
    for child in sorted(node.iterdir(), key=lambda p: p.name.lower()):
        if child.name.startswith("."):
            continue
        child_rel = f"{rel}/{child.name}" if rel else child.name
        if child.is_dir():
            if is_module_dir(child):
                entries.append((child.name, f'"@{alias}/{child_rel}"'))
            else:
                entries.append((child.name, build(child, alias, child_rel, indent + 1)))
        elif child.suffix in (".luau", ".lua") and child.stem != "init":
            name = module_name(child)
            leaf_rel = f"{rel}/{name}" if rel else name
            entries.append((name, f'"@{alias}/{leaf_rel}"'))
    lines = [f"{inner}{name} = {value}," for name, value in entries]
    return "folder({\n" + "\n".join(lines) + f"\n{pad}}})"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="Source dir to mirror (default: .luaurc alias path).")
    parser.add_argument("--alias", default="ReplicatedStorage", help="Alias name (default ReplicatedStorage).")
    parser.add_argument("--luaurc", default=".luaurc", help="Path to .luaurc (default ./.luaurc).")
    args = parser.parse_args()

    root = Path(args.root).resolve() if args.root else alias_from_luaurc(Path(args.luaurc), args.alias)
    if not root or not root.is_dir():
        raise SystemExit(f"Source root not found (root={root}). Pass --root explicitly.")

    tree = build(root, args.alias, "", 0)
    print("-- BEGIN module tree (scaffold_module_tree.py)")
    print(f"local {args.alias} = {tree}")
    print("-- END module tree")


if __name__ == "__main__":
    main()
