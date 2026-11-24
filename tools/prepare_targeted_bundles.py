#!/usr/bin/env python3
"""
Targeted Bundle Preparer for KAT-Coder Audits
Creates focused bundles for specific sub-systems:
1. Physics & Collision (src/physics.rs, src/engine.rs)
2. Roadnet & Bridges (game/lib/roadnet.lua, game/lib/city.lua)
3. Rendering & Graphics (src/render.rs, src/mesh.rs)
"""

import os

BASE_DIR = "/home/olivermikkola/Projects/3D-auto"
OUTPUT_DIR = "/home/olivermikkola/Projects/3D-auto/docs/audit/prompts"

MODULES = {
    "physics_collision": [
        "src/physics.rs",
        "src/engine.rs",
    ],
    "roadnet_bridges": [
        "game/lib/roadnet.lua",
    ],
    "render_memory": [
        "src/render.rs",
        "src/mesh.rs",
    ],
}

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name, files in MODULES.items():
        content = [f"# TARGETED AUDIT: {name}\n"]
        total_lines = 0
        for rel_path in files:
            full_path = os.path.join(BASE_DIR, rel_path)
            with open(full_path, "r", encoding="utf-8") as f:
                code = f.read()
            total_lines += len(code.splitlines())
            content.append(f"\n--- FILE: {rel_path} ---\n```{rel_path.split('.')[-1]}\n{code}\n```\n")
        out_path = os.path.join(OUTPUT_DIR, f"targeted_{name}.txt")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("".join(content))
        print(f"Generated {out_path}: {total_lines} lines ({len(''.join(content))} bytes)")

if __name__ == "__main__":
    main()
