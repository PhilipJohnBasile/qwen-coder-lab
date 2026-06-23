# A near-frontier coding model, running on a laptop — and an honest look at what actually makes it better

**TL;DR:** I put a clean, near-frontier open coding model (**Qwen3-Coder-Next**, 80B total / 3B active) on a single **M5 Max MacBook (128 GB)**, all MLX-native, and ran a careful overnight experiment to find what actually moves the needle: a better base, test-time compute (a verify-and-repair loop), or fine-tuning. Everything was measured by *actually compiling and running* each solution's hidden tests — no vibes, no self-reported scores.

Repo (code, scripts, results, research): **https://github.com/PhilipJohnBasile/qwen-coder-lab**

---

## The numbers (all measured locally, verifier-scored)

| Probe | Result |
|---|---|
| **HumanEval-164**, single-shot | **93.3%** |
| **HumanEval-164** + verify-and-repair loop | **97.6%** |
| **MBPP-500**, single-shot | **75.4%** |
| **MBPP-500** + verify-and-repair loop | **88.4%** |

For context, the *previous* experiment had crushed a 744B model down to fit the same laptop and topped out at **69%** on HumanEval. A clean, right-sized model **smokes it (93.3%)** — and runs far faster (only 3B parameters active per token).

## The three levers, ranked by what actually helped

1. **🥇 The right base.** A clean near-frontier model beats a heavily-compressed giant, decisively. Pick the best *quality-per-active-param* model that fits your memory, not the biggest one you can cram in.
2. **🥈 Test-time compute.** Wrapping generations in a verify-and-repair loop (run the code, feed the real error back, retry) added **+4 pts on HumanEval and +13 on MBPP** — for *zero* training. Cheapest, most reliable win.
3. **🥉 Fine-tuning: essentially a no-op here.** A full-epoch LoRA "heal" on 5,600 curated examples came out **flat on MBPP (75.4→75.0) and slightly *negative* on HumanEval (93.3→90.9)**. Healing a model already near its ceiling risks mild forgetting, not gains. Honest result, exactly matching the prior project's finding and the current research.

**The takeaway:** for a strong modern base, *test-time compute beats weight-surgery*. Spend your effort on the verify loop, not the fine-tune.

## One thing I'm a little proud of

The fine-tune first looked "perfectly neutral" — byte-identical scores. That smelled wrong. Turned out the serving path was **silently ignoring the adapter** (a real gotcha: `mlx_lm.server --adapter-path` served the base). I caught it, re-ran the comparison in a path where the adapter was provably live, and *that's* how the true −0.4 / −2.4 came out instead of a false "no change." The whole point was to measure honestly, including measuring whether the measurement was real.

## How it was built

Fully autonomous overnight run on the laptop, using **every compute block** of the M5 Max: GPU+matrix units for training/inference, the **Neural Engine** for embedding the corpus, CPU for the verifier sandbox, network for model pulls — nothing idle. Crash-tolerant drivers, auto-shrinking config when training hit a memory wall, and a parallel research agent that produced a cited June-2026 SOTA brief (also in the repo).

---

*Stack: Qwen3-Coder-Next (MLX 8-bit) · mlx-lm · a tiny verify-first harness ([agent-toolkit](https://github.com/PhilipJohnBasile/agent-toolkit)) · one M5 Max, 128 GB. All MIT.*
