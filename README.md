# qwen-coder-lab 🧪

The **up-path** experiment: take a clean, near-frontier, right-sized base — **Qwen3-Coder-Next
(80B total / 3B active)** — and test whether the methods that were *neutral on the demolished
GLM-5.2 base* actually **lift a base that fights back**.

> The demolished 744B → 98 GB GLM-5.2 hit its ceiling at **HumanEval-164 = 69%**. Souls/heals were
> measured *neutral-to-degrading* on it. The thesis: on a clean base they lift. This lab measures that.

## Why this config (M5 Max, 128 GB, MLX-first)

| Choice | Pick | Why |
|---|---|---|
| **Model** | Qwen3-Coder-Next **80B-A3B** (MLX 8-bit) | Fits 128 GB (≈80 GB @ 8-bit, ≈40 GB @ 4-bit), **70.6% SWE-bench Verified** ≈ near-frontier, **3B active = fast** |
| **Harness** | **Pi** | MLX-native, <1K-token system prompt, Mac-tuned — matches the MLX-first principle |
| **Verify** | [agent-toolkit](https://github.com/PhilipJohnBasile/agent-toolkit) `verify_domain()` | compile/test-gate every generation (the core idea that *did* carry forward) |
| **Heal data** | [glm52-demolition-data](https://huggingface.co/datasets/philipjohnbasile/glm52-demolition-data) | 272K verified FOCUS-9 examples + per-facet soul gold |

The **480B-A35B** is stronger but won't fit 128 GB at usable quant (~240 GB @ 4-bit). Next's
3B-active is the sweet spot for our box.

## The staged experiment (cheap → expensive)

| Stage | What | Cost | The number |
|---|---|---|---|
| **0** | Get the base (`scripts/00_get_model.sh`) | ~20 min | — |
| **1** | Baseline HumanEval-164, **raw** (`scripts/01_baseline.py`) | ~30 min | clean-base pass@1 vs demolished **69%** |
| **2** | + verify-loop lift, best-of-N gated (`scripts/02_verify_loop.py`) | ~1 hr | raw vs +verify Δ |
| **3** | LoRA-heal on FOCUS-9 gold → re-bench | training | does healing lift a clean base? |
| **4** | mount one soul (security/design) via canon → facet probe | training | facet lift |
| **5** | drive with Pi/merle on a real repo task | — | task solved Y/N |

**Discipline (inherited from the demolition):** one honest measured number per stage. Never fake it.
`HEAL max-seq ≤ 2048` · `enable_thinking=false` for code bench · clean stale MLX procs before any serve.

## Quickstart

```bash
cd /Users/pjb/git/qwen-coder-lab
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # mlx-lm, datasets, + agent-toolkit on path

bash scripts/00_get_model.sh             # pull the MLX build (8-bit)
bash scripts/05_serve.sh                 # serve on :8080 (one model resident — never double-load)
python scripts/01_baseline.py --n 164    # the headline: clean vs demolished 69%
```

## Layout
```
scripts/00_get_model.sh   # pull Qwen3-Coder-Next MLX 8-bit (lms / hf)
scripts/05_serve.sh       # mlx_lm.server on :8080, single resident model
scripts/01_baseline.py    # HumanEval-164 raw pass@1, verifier-scored
scripts/02_verify_loop.py # best-of-N + verify_domain() gate → the lift number
RESULTS.md                # the running scoreboard (fill as stages land)
```

## Pairs with
- [agent-toolkit](https://github.com/PhilipJohnBasile/agent-toolkit) — verifiers + soul canons + flywheels
- [merle](https://github.com/PhilipJohnBasile/merle) — verifier-first coding CLI (`MERLE_BASE`)
- [Pi](https://github.com/bradAGI/awesome-cli-coding-agents) — the MLX-native local harness

## License
MIT.
