#!/usr/bin/env python3
"""Stage 1 — HumanEval-164 raw pass@1, verifier-scored, against a served base.

The headline: clean Qwen3-Coder-Next pass@1 vs the demolished GLM-5.2's 69%.
Single-shot, enable_thinking=false, scored by agent-toolkit's real python verifier
(compile+run the hidden test) — comparable to the demolition's scripts/58_bench.py.

Usage:
  python scripts/01_baseline.py --n 164 [--base http://localhost:8080/v1]
Requires: a served base (scripts/05_serve.sh) + agent-toolkit on the path.
"""
import argparse, json, os, re, sys, urllib.request

# --- wire in agent-toolkit's verifier (sibling clone or $AGENT_TOOLKIT) ----------------
TK = os.environ.get("AGENT_TOOLKIT",
                    os.path.join(os.path.dirname(__file__), "..", "..", "agent-toolkit"))
sys.path.insert(0, os.path.abspath(TK))
from verify.verifiers import verify_domain  # noqa: E402


def chat(base, model, prompt, max_tokens=1024):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(base.rstrip("/") + "/chat/completions",
                                 data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read())["choices"][0]["message"]["content"]


def extract_code(text):
    m = re.search(r"```(?:python)?\s*(.*?)```", text, re.S)
    return (m.group(1) if m else text).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=164)
    ap.add_argument("--base", default=os.environ.get("BASE", "http://localhost:8080/v1"))
    ap.add_argument("--model", default=os.environ.get("MODEL", "qwen3-coder-next"))
    args = ap.parse_args()

    from datasets import load_dataset
    ds = load_dataset("openai/openai_humaneval", split="test")
    if args.n < len(ds):
        ds = ds.select(range(args.n))

    passed = 0
    for i, ex in enumerate(ds):
        prompt = ("Complete this Python function. Return ONLY the full function in a "
                  "```python code block.\n\n" + ex["prompt"])
        try:
            code = extract_code(chat(args.base, args.model, prompt))
        except Exception as e:
            print(f"[{i:3}] {ex['task_id']:16} GEN-ERR {e}"); continue
        harness = ex["test"] + f"\ncheck({ex['entry_point']})\n"
        r = verify_domain("python", code, harness=harness)
        passed += bool(r.passed)
        print(f"[{i:3}] {ex['task_id']:16} {'PASS' if r.passed else 'fail '+r.stage}")

    n = len(ds)
    print(f"\n== HumanEval-{n} pass@1 = {passed}/{n} = {100*passed/n:.1f}%  "
          f"(demolished GLM-5.2 baseline: 69%)")


if __name__ == "__main__":
    main()
