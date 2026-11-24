#!/usr/bin/env python3
"""
KAT-Coder Code Simplicity & Zero-Dependency Refactoring Pass
Prompts KAT-Coder to find over-engineered code, duplicate math/utility logic,
and propose clean, stdlib-only simplifications.
"""

import os
import sys
import json
import time
import urllib.request

API_URL = "http://127.0.0.1:8088/v1/chat/completions"
AUDIT_DIR = "/home/olivermikkola/Projects/3D-auto/docs/audit"
PROMPT_DIR = os.path.join(AUDIT_DIR, "prompts")

SYSTEM_PROMPT = """You are a Principal Software Engineer obsessed with minimalism, extreme code clarity, and zero-dependency idiomatic software design (Rob Pike, Carmack style).
Your mission: Scour the code for over-engineering, unnecessary abstractions, duplicate vector math, bloated table handling, and accidental complexity.
Rules:
1. NO new external dependencies/crates/libraries. Use ONLY Rust standard library and existing Lua 5.4 features.
2. Recommend code deletions, simplifications, and inline cleanups.
3. Show exact Before -> After code snippets with line numbers."""

USER_PROMPT = """Analyze `src/math.rs`, `src/engine.rs`, and `game/lib/util.lua`.
Find:
1. Over-complicated math or vector operations that can be written in half the lines.
2. Accidental complexity in entity management, tagged lookups, or light handling.
3. Clean Lua helper simplifications in `util.lua` that eliminate garbage collection pressure and repetitive boilerplate across systems.

Here is the source code:

--- FILE: src/math.rs ---
{math_code}

--- FILE: src/engine.rs ---
{engine_code}

--- FILE: game/lib/util.lua ---
{util_code}
"""

def main():
    with open("/home/olivermikkola/Projects/3D-auto/src/math.rs", "r") as f:
        math_code = f.read()
    with open("/home/olivermikkola/Projects/3D-auto/src/engine.rs", "r") as f:
        engine_code = f.read()
    with open("/home/olivermikkola/Projects/3D-auto/game/lib/util.lua", "r") as f:
        util_code = f.read()
        
    prompt = USER_PROMPT.format(math_code=math_code, engine_code=engine_code, util_code=util_code)
    print(f"[REFACTOR PASS] Starting Zero-Dependency Simplicity Audit (Prompt size: {len(prompt)} chars)...")
    
    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 1500,
        "temperature": 0.1,
    }
    
    req = urllib.request.Request(API_URL, data=json.dumps(payload).encode("utf-8"), headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1200) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t0
            choice = res["choices"][0]
            content = choice["message"].get("content", "")
            reasoning = choice["message"].get("reasoning_content", "")
            usage = res.get("usage") or {}
            
            out_file = os.path.join(AUDIT_DIR, "03_code_simplicity_zero_dep_report.md")
            with open(out_file, "w", encoding="utf-8") as f:
                f.write("# KAT-Coder Audit Report: Zero-Dependency Simplicity & Code Cleanup\n\n")
                f.write(f"**Generated:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"**Elapsed Time:** {elapsed:.1f}s\n")
                f.write(f"**Tokens:** {usage.get('total_tokens', 0)} (Prompt: {usage.get('prompt_tokens', 0)}, Output: {usage.get('completion_tokens', 0)})\n\n")
                if reasoning:
                    f.write(f"## Reasoning Trace\n\n```\n{reasoning}\n```\n\n")
                f.write("## Proposed Simplifications & Refactorings\n\n")
                f.write(content or "*(See reasoning trace)*")
            print(f"[REFACTOR PASS COMPLETE] Report written to: {out_file} (Took {elapsed:.1f}s)")
    except Exception as e:
        print(f"[REFACTOR PASS ERROR] {e}")

if __name__ == "__main__":
    main()
