#!/usr/bin/env python3
"""
3D-Auto Codebase Bundle Preparer for Local LLM Scour
Packs Rust engine kernel and Lua systems into clean, structured prompts.
Omits raw multi-megabyte OSM coordinate tables.
"""

import os
import sys

BASE_DIR = "/home/olivermikkola/Projects/3D-auto"
OUTPUT_DIR = "/home/olivermikkola/Projects/3D-auto/docs/audit/prompts"

RUST_FILES = [
    "src/main.rs",
    "src/engine.rs",
    "src/physics.rs",
    "src/render.rs",
    "src/script.rs",
    "src/audio.rs",
    "src/pad.rs",
    "src/save.rs",
    "src/math.rs",
    "src/mesh.rs",
]

LUA_CORE = [
    "game/main.lua",
    "game/lib/city.lua",
    "game/lib/roadnet.lua",
    "game/lib/prefabs.lua",
    "game/lib/hud.lua",
    "game/lib/menu.lua",
    "game/lib/mission.lua",
    "game/lib/borders.lua",
    "game/lib/map_viewer.lua",
    "game/systems/peds.lua",
    "game/systems/police.lua",
    "game/systems/aurajoki.lua",
]

def bundle_files(file_list, title):
    content = [f"# CODEBASE AUDIT: {title}\n"]
    for rel_path in file_list:
        full_path = os.path.join(BASE_DIR, rel_path)
        if os.path.exists(full_path):
            with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                code = f.read()
            content.append(f"\n--- FILE: {rel_path} ---\n```{rel_path.split('.')[-1]}\n{code}\n```\n")
        else:
            print(f"Warning: file not found: {full_path}")
    return "".join(content)

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # 1. Rust Engine Bundle
    rust_bundle = bundle_files(RUST_FILES, "Rust Engine Kernel")
    rust_out = os.path.join(OUTPUT_DIR, "01_rust_kernel_bundle.txt")
    with open(rust_out, "w", encoding="utf-8") as f:
        f.write(rust_bundle)
    print(f"Wrote Rust bundle: {rust_out} ({len(rust_bundle.splitlines())} lines, {len(rust_bundle)} bytes)")
    
    # 2. Lua Systems Bundle
    lua_bundle = bundle_files(LUA_CORE, "Lua Gameplay & Systems Architecture")
    lua_out = os.path.join(OUTPUT_DIR, "02_lua_systems_bundle.txt")
    with open(lua_out, "w", encoding="utf-8") as f:
        f.write(lua_bundle)
    print(f"Wrote Lua bundle: {lua_out} ({len(lua_bundle.splitlines())} lines, {len(lua_bundle)} bytes)")

if __name__ == "__main__":
    main()
