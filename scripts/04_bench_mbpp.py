#!/usr/bin/env python3
"""Harder/broader probe — MBPP (full, 500 test problems), verifier-scored.

A second, broader code distribution than HumanEval — 500 problems, assert-based.
Same honest grading: model returns a function, we run the real test_list asserts through
agent-toolkit's python verifier. Reuses 01_baseline's chat/extract/verify wiring.

Usage: python scripts/04_bench_mbpp.py --n 500 [--loop K]   (--loop adds verifier-repair)
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from importlib import import_module
b = import_module("01_baseline")


def harness_for(ex):
    setup = ex.get("test_setup_code", "") or ""
    return setup + "\n" + "\n".join(ex["test_list"]) + "\n"


def prompt_for(ex):
    # MBPP convention: reveal the signature via the first assert
    return (f"{ex['text'].strip()}\n\nYour code must pass this test: {ex['test_list'][0]}\n"
            "Return ONLY the function in a ```python code block.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--loop", type=int, default=1, help="repair budget k (1 = single-shot)")
    ap.add_argument("--base", default=os.environ.get("BASE", "http://localhost:8080/v1"))
    ap.add_argument("--model", default=os.environ.get("MODEL", "qwen3-coder-next"))
    args = ap.parse_args()

    from datasets import load_dataset
    ds = load_dataset("google-research-datasets/mbpp", "full", split="test")
    if args.n < len(ds):
        ds = ds.select(range(args.n))

    passed = 0
    for i, ex in enumerate(ds):
        harness, base_prompt = harness_for(ex), prompt_for(ex)
        ok, diag = False, ""
        for attempt in range(args.loop):
            p = base_prompt if not diag else base_prompt + f"\n\nPrevious attempt failed:\n{diag[:700]}\nFix it."
            try:
                code = b.extract_code(b.chat(args.base, args.model, p))
            except Exception:
                continue
            r = b.verify_domain("python", code, harness=harness)
            if r.passed:
                ok = True; break
            diag = r.diag
        passed += ok
        print(f"[{i:3}] {ex['task_id']} {'PASS' if ok else 'fail'}")

    n = len(ds)
    tag = f"+loop(k={args.loop})" if args.loop > 1 else "raw"
    print(f"\n== MBPP-{n} {tag} pass@1 = {passed}/{n} = {100*passed/n:.1f}%  "
          f"(HumanEval ref: 93.3% raw / 97.6% +loop)")


if __name__ == "__main__":
    main()
