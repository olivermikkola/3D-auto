#!/usr/bin/env python3
"""
KAT-Coder Deep Engine Scour Runner
Runs independent audit passes via local KAT-Coder-V2.5-Dev.
Saves structured markdown reports to docs/audit/
"""

import os
import sys
import json
import time
import urllib.request

API_URL = "http://127.0.0.1:8088/v1/chat/completions"
AUDIT_DIR = "/home/olivermikkola/Projects/3D-auto/docs/audit"
PROMPT_DIR = os.path.join(AUDIT_DIR, "prompts")

PASSES = [
    {
        "name": "01_rust_physics_collision",
        "file": "targeted_physics_collision.txt",
        "system": "You are a veteran systems engineer and game engine architect specializing in vehicular physics, raycasting, and AABB broad-phase solvers.",
        "task": (
            "Analyze `src/physics.rs` and `src/engine.rs`. Focus on:\n"
            "1. Raycasting edge-cases against static bodies and terrain.\n"
            "2. Potential causes of vehicle snagging or spurious collision impulses on road seams.\n"
            "3. Concurrency, memory efficiency, and solver determinism.\n"
            "Cite exact line numbers and functions. Suggest clean, minimal patches."
        ),
        "max_tokens": 1500,
    },
    {
        "name": "02_lua_roadnet_bridges",
        "file": "targeted_roadnet_bridges.txt",
        "system": "You are a senior tools programmer and procedural generation architect specializing in road networks, bridge elevations, and mesh generation.",
        "task": (
            "Analyze `game/lib/roadnet.lua`. Focus on:\n"
            "1. Bridge elevation ramps overlapping adjacent roads (e.g. approach slabs clipping into perpendicular or parallel surface lanes).\n"
            "2. Bridge collision boxes and how clearance is maintained over water and crossings.\n"
            "3. Table churn and GC hotspots during city/road generation.\n"
            "Provide concrete line citations and proposed Lua code fixes."
        ),
        "max_tokens": 1500,
    }
]

def query_kat(system_prompt: str, user_prompt: str, max_tokens: int = 1500) -> dict:
    payload = {
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        "max_tokens": max_tokens,
        "temperature": 0.2,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API_URL, data=data, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1200) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t0
            choice = res["choices"][0]
            msg = choice["message"]
            content = msg.get("content", "")
            reasoning = msg.get("reasoning_content", "")
            usage = res.get("usage", {})
            return {
                "content": content,
                "reasoning": reasoning,
                "elapsed": elapsed,
                "usage": usage
            }
    except Exception as e:
        return {"error": str(e)}

def run_pass(p):
    bundle_path = os.path.join(PROMPT_DIR, p["file"])
    if not os.path.exists(bundle_path):
        print(f"File not found: {bundle_path}")
        return
    with open(bundle_path, "r", encoding="utf-8") as f:
        code_bundle = f.read()
    
    full_user_prompt = f"{p['task']}\n\nHere is the codebase:\n\n{code_bundle}"
    print(f"\n[AUDIT] Starting Pass: {p['name']} (Prompt size: {len(full_user_prompt)} chars)...")
    res = query_kat(p["system"], full_user_prompt, p["max_tokens"])
    
    if "error" in res:
        print(f"[AUDIT ERROR] {res['error']}")
        return
        
    out_file = os.path.join(AUDIT_DIR, f"{p['name']}_report.md")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(f"# KAT-Coder Audit Report: {p['name']}\n\n")
        f.write(f"**Generated:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"**Elapsed Time:** {res['elapsed']:.1f}s\n")
        usage = res.get("usage") or {}
        f.write(f"**Tokens:** {usage.get('total_tokens', 0)} (Prompt: {usage.get('prompt_tokens', 0)}, Output: {usage.get('completion_tokens', 0)})\n\n")
        if res.get("reasoning"):
            f.write(f"## Reasoning Trace\n\n```\n{res['reasoning']}\n```\n\n")
        f.write("## Findings & Actionable Recommendations\n\n")
        f.write(res.get("content") or "*(No direct content, see reasoning trace)*")
        
    print(f"[AUDIT COMPLETE] Wrote report to: {out_file} (Took {res['elapsed']:.1f}s)")

def main():
    for p in PASSES:
        out_file = os.path.join(AUDIT_DIR, f"{p['name']}_report.md")
        if os.path.exists(out_file):
            print(f"[AUDIT] Skipping already completed pass: {p['name']}")
            continue
        run_pass(p)

if __name__ == "__main__":
    main()
