#!/usr/bin/env python3
"""Stage 2 — verify-loop LIFT: best-of-N sampling, verifier-gated, repair from the diag.

Measures the Δ over Stage 1's raw pass@1 with NO training — the #113 lever. On a stronger
base this should lift more than it did on the crippled demolished one. Keep the first sample
that passes verify_domain(); on failure, feed the real compiler/runtime diag back once.

Usage: python scripts/02_verify_loop.py --n 164 --k 4
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from importlib import import_module
b = import_module("01_baseline")  # reuse chat/extract_code/verify_domain wiring


def solve(base, model, ex, k):
    prompt = ("Complete this Python function. Return ONLY the full function in a "
              "```python code block.\n\n" + ex["prompt"])
    harness = ex["test"] + f"\ncheck({ex['entry_point']})\n"
    last_diag = ""
    for attempt in range(k):
        p = prompt if not last_diag else (
            prompt + f"\n\nYour previous attempt failed:\n{last_diag[:800]}\nFix it.")
        try:
            code = b.extract_code(b.chat(base, model, p))
        except Exception:
            continue
        r = b.verify_domain("python", code, harness=harness)
        if r.passed:
            return True, attempt + 1
        last_diag = r.diag
    return False, k


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=164)
    ap.add_argument("--k", type=int, default=4, help="best-of/repair budget")
    ap.add_argument("--base", default=os.environ.get("BASE", "http://localhost:8080/v1"))
    ap.add_argument("--model", default=os.environ.get("MODEL", "qwen3-coder-next"))
    args = ap.parse_args()

    from datasets import load_dataset
    ds = load_dataset("openai/openai_humaneval", split="test")
    if args.n < len(ds):
        ds = ds.select(range(args.n))

    passed = tries = 0
    for i, ex in enumerate(ds):
        ok, used = solve(args.base, args.model, ex, args.k)
        passed += ok; tries += used
        print(f"[{i:3}] {ex['task_id']:16} {'PASS' if ok else 'fail'} (k={used})")

    n = len(ds)
    print(f"\n== HumanEval-{n} +verify-loop (k={args.k}) pass@1 = {passed}/{n} = "
          f"{100*passed/n:.1f}%  | avg attempts {tries/n:.2f}  | raw baseline in Stage 1")


if __name__ == "__main__":
    main()
