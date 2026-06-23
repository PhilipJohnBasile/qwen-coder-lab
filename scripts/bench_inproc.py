#!/usr/bin/env python3
"""In-process bench that GUARANTEES the adapter is applied (loads model+adapter directly via
mlx_lm.load, not the HTTP server). The overnight server path silently failed to apply the LoRA,
giving base-identical numbers — this is the trustworthy A/B. Same verifier scoring.

Usage: python scripts/bench_inproc.py --bench mbpp --n 500 [--adapter heal/adapters-focus9]
       python scripts/bench_inproc.py --bench he   --n 164 [--adapter ...]
"""
import argparse, os, re, sys
TK = os.path.join(os.path.dirname(__file__), "..", "..", "agent-toolkit")
sys.path.insert(0, os.path.abspath(TK))
from verify.verifiers import verify_domain
from mlx_lm import load, generate
from mlx_lm.sample_utils import make_sampler


def extract_code(t):
    m = re.search(r"```(?:python)?\s*(.*?)```", t, re.S)
    return (m.group(1) if m else t).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", choices=["mbpp", "he"], required=True)
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--adapter", default=None)
    ap.add_argument("--model", default="models/qwen3-coder-next-8bit")
    args = ap.parse_args()

    model, tok = load(args.model, adapter_path=args.adapter)
    sampler = make_sampler(temp=0.0)
    tag = "HEALED" if args.adapter else "BASE"

    def gen(content, mx=1024):
        msgs = [{"role": "user", "content": content}]
        try:
            prompt = tok.apply_chat_template(msgs, add_generation_prompt=True,
                                             chat_template_kwargs={"enable_thinking": False})
        except Exception:
            prompt = tok.apply_chat_template(msgs, add_generation_prompt=True)
        return generate(model, tok, prompt=prompt, max_tokens=mx, sampler=sampler, verbose=False)

    from datasets import load_dataset
    passed = 0
    if args.bench == "mbpp":
        ds = load_dataset("google-research-datasets/mbpp", "full", split="test")
        ds = ds.select(range(min(args.n, len(ds))))
        for i, ex in enumerate(ds):
            p = (f"{ex['text'].strip()}\n\nYour code must pass this test: {ex['test_list'][0]}\n"
                 "Return ONLY the function in a ```python code block.")
            code = extract_code(gen(p))
            h = (ex.get("test_setup_code", "") or "") + "\n" + "\n".join(ex["test_list"]) + "\n"
            r = verify_domain("python", code, harness=h)
            passed += bool(r.passed)
            if i % 25 == 0:
                print(f"[{i}] running {passed}/{i+1}", flush=True)
    else:
        ds = load_dataset("openai/openai_humaneval", split="test")
        ds = ds.select(range(min(args.n, len(ds))))
        for i, ex in enumerate(ds):
            p = ("Complete this Python function. Return ONLY the full function in a "
                 "```python code block.\n\n" + ex["prompt"])
            code = extract_code(gen(p))
            h = ex["test"] + f"\ncheck({ex['entry_point']})\n"
            r = verify_domain("python", code, harness=h)
            passed += bool(r.passed)

    n = len(ds)
    print(f"\n== {tag} {args.bench.upper()}-{n} (in-proc, adapter={'YES' if args.adapter else 'no'}) "
          f"pass@1 = {passed}/{n} = {100*passed/n:.1f}%")


if __name__ == "__main__":
    main()
