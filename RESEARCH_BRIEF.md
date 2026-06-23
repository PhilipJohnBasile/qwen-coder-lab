# Research Brief — Local Coding Models, LoRA Healing, MLX Training, Agentic Harnesses, Verify-First

**Date:** 2026-06-22
**Scope:** Tailored to our stack — clean Qwen3-Coder-Next (80B total / 3B active), MLX 8-bit, M5 Max 128GB, served via `mlx_lm`, verify-first harness (compile/run-gate every gen). Measured locally: HumanEval-164 = 93.3% raw / 97.6% with verifier-repair; MBPP-500 = 75.4% raw.

> **Method note / caveats.** Every benchmark number below is cross-checked against ≥2 sources. Where sources disagree (they frequently do for SWE-bench Verified), the spread is shown. **SWE-bench Verified is now widely considered contaminated/saturated** — OpenAI itself flagged training-data contamination across frontier models, and the field is migrating to **SWE-bench Pro** (multi-language, standardized scaffold) as the more reliable signal ([benchmarkingagents.com](https://benchmarkingagents.com/swe-bench/), [morphllm.com/swe-bench-pro](https://www.morphllm.com/swe-bench-pro)). Treat single-source "leader" claims skeptically; the scaffold matters as much as the model.

---

## 1. June 2026 SOTA Local Coding Models

### The landscape
The open-weight coding frontier in mid-2026 is dominated by Chinese labs (DeepSeek, Moonshot/Kimi, Zhipu/GLM, Alibaba/Qwen) plus Mistral (Devstral) and MiniMax. The headline open models are huge MoEs (0.7T–1.6T total) that **do not fit our 128GB box**. Our Qwen3-Coder-Next sits in a different, deliberately-chosen niche: best quality *per active parameter*, and one of the very few strong models that actually runs well on Apple Silicon.

### Benchmark table (open-weight models, cross-checked)

| Model | Total / Active | Ctx | SWE-bench Verified | LiveCodeBench | Aider Polyglot | Fits 128GB Mac? |
|---|---|---|---|---|---|---|
| **DeepSeek V4-Pro (Max)** | ~1.6T / 49B | 1M | **80.6%** ¹ (V4-Pro-High 79.4% ²) | **93.5** (LCB #1) ¹ | — | ❌ way too big |
| **Kimi K2.6** (Moonshot) | ~1T / 32B | 256K | **80.2%** ² | 89.6 ¹ | — | ❌ |
| **GLM-5 / 5.1 / 5.2** (Zhipu) | 744B / 40B | 200K | **77.8%** (GLM-5) ² | — | — | ❌ (our demolition project's target) |
| **MiniMax M3** (Jun 2026) | MoE / — | 1M | 80.5% ³ (SWE-Pro 59.0%) ¹ | — | — | ❌ |
| **DeepSeek V4-Flash** | 284B / 13B | 1M | 79.0% ¹ | 91.6 ¹ | — | ⚠️ tight at low quant / single-H100 class |
| **Devstral 2** (Mistral) | 123B dense-ish | 256K | 72.2% ¹ | 66.79 ¹ | — | ⚠️ at 4-bit |
| **Qwen3.6-27B** (dense) | 27B dense | 262K | 77.2% ¹ | — | — | ✅ comfortably |
| **Qwen3-Coder-Next (ours)** | **80B / 3B** | **262K** | **70.6 / 71.1 / 71.3%** (SWE-Agent / MiniSWE / OpenHands) ⁴ | 58.93 (v6) ⁴ | 66.20 ⁴ | ✅ **our model** |

Sources: ¹ [kilo.ai/open-source-models](https://kilo.ai/open-source-models); ² [benchlm.ai/benchmarks/sweVerified](https://benchlm.ai/benchmarks/sweVerified); ³ [tokenmix.ai](https://tokenmix.ai/blog/best-chinese-ai-models-2026-comparison-guide); ⁴ Qwen3-Coder-Next Technical Report [arxiv 2603.00729](https://arxiv.org/html/2603.00729v1) + [qwen.ai blog](https://qwen.ai/blog?id=qwen3-coder-next).

**Cross-check on Qwen3-Coder-Next SWE-bench:** the technical report, the Qwen blog, and third-party writeups ([n1n.ai](https://explore.n1n.ai/blog/qwen3-coder-next-architecture-performance-analysis-2026-05-22), [marktechpost](https://www.marktechpost.com/2026/02/03/)) all agree on **70.6% (SWE-Agent) → 71.3% (OpenHands)**. The report claims it *matches DeepSeek-V3.2 (671B-A37B) and GLM-4.7 (358B-A32B) on SWE-bench Verified despite far fewer active params* — a per-active-param efficiency claim, not an absolute-quality claim. That framing is consistent across sources and is the right lens for us.

### Verdict for a 128GB Apple Silicon box
- **The genuine frontier models (DeepSeek V4, Kimi K2.6, GLM-5.x, MiniMax M3) do NOT fit.** They are 0.7–1.6T params; even at 4-bit they blow past 128GB. This matches our own prior finding (`demolition-vs-clean-base`): a clean ~30–80B model beats a demolished 743B on our hardware.
- **The realistic local SOTA for us is exactly the bracket we're in:** Qwen3-Coder-Next (80B-A3B) and Qwen3.6-27B dense. Qwen3-Coder-Next is the best *agentic* fit because it was explicitly trained on tool-calling templates (21 variations) and executable verifiable tasks ([arxiv 2603.00729](https://arxiv.org/html/2603.00729v1)).
- **Watch:** **DeepSeek V4-Flash (284B-A13B)** is the only "frontier-flavored" model plausibly squeezable at aggressive quant — worth a feasibility test, but A13B will be ~4× slower per token than our A3B and quality at 3-bit is unproven.
- **Reality check on our own numbers:** our HumanEval 93.3% raw is *above* what these SWE-bench numbers might suggest, because HumanEval/MBPP are far easier and more saturated than SWE-bench. Do **not** infer SWE-bench-grade capability from our HumanEval/MBPP results. If we want a defensible capability claim, we need to run SWE-bench Verified (or better, SWE-bench Pro) locally with a real scaffold.

---

## 2. LoRA / SFT Healing a Strong Coder Without Catastrophic Forgetting

### The core risk
Recent work (late-2025/2026) is blunt: **LoRA does NOT inherently prevent forgetting.** It minimizes raw-weight change but does not preserve *functional behavior* on prior tasks ([arxiv 2510.13003 OPLoRA](https://arxiv.org/html/2510.13003v2), [arxiv 2512.17720](https://arxiv.org/pdf/2512.17720)). For a near-saturated coder this is the dominant danger: it's far easier to *degrade* HumanEval-93/MBPP-75 than to lift it.

### What actually lifts vs degrades a strong coder
- **Replay / data mixing is the single highest-leverage lever.** Mix 5–25% general/instruction + prior-distribution data into the heal set. Multiple sources converge: 15–25% replay gives most of the anti-forgetting benefit; ~50/50 is the "safe but 2× cost" regime; >50% starts hurting plasticity (redundancy/noise), and even withholding replay for ~3% of samples measurably degrades retention ([brics-econ.org](https://brics-econ.org/preventing-catastrophic-forgetting-during-llm-fine-tuning-techniques-that-work), [arxiv 2505.12512](https://arxiv.org/html/2505.12512v1), [futureagi.com](https://futureagi.com/blog/llm-fine-tuning-techniques-i-ii/)). **For us: 80–85% custom code + 15–20% replay of HumanEval/MBPP-style + general instruction.**
- **Learning rate is the #1 knob and the #1 way to wreck a strong model.** Consensus range 1e-5 to 5e-4; **start low (1e-5 to 5e-5)** for a saturated model. A Feb-2026 study ([arxiv 2602.04998](https://arxiv.org/html/2602.04998v1)) found that *once LR is properly tuned, vanilla LoRA matches DoRA/PiSSA* — i.e., LR tuning dominates method choice.
- **DoRA vs LoRA vs PiSSA:** DoRA "consistently outperforms LoRA" in NVIDIA/other reports and closes ~half the LoRA→full-FT gap for +5–10% memory ([NVIDIA blog](https://developer.nvidia.com/blog/introducing-dora-a-high-performing-alternative-to-lora-for-fine-tuning/), [spheron](https://www.spheron.network/blog/peft-methods-2026-dora-galore-pissa-vera-guide/)), BUT the LR-tuning paper says the edge collapses once LR is tuned. **PiSSA** gives faster convergence (better init). **Practical call:** start with well-tuned **LoRA**; only reach for **DoRA** if you have memory headroom and a measured plateau. Suggested default seen repeatedly: **r=16, alpha=32, target = all-linear**.
- **Rank:** for a strong base, **small rank (8–16)** is safer — high rank = more capacity to overwrite pretrained behavior. Higher rank only if the heal data is large and genuinely new-domain.
- **Layers/modules:** target attention proj (q/k/v/o) ± MLP. For an MoE, **be careful around router/gate weights** (see below).
- **MoE-specific:** This is the subtlety for our A3B model. Naive LoRA on a sparse MoE can imbalance routing. Research lines worth knowing: **LoRA-MoE** (token-routed adapters explicitly reduce forgetting), **GuiLoMo** (bilevel allocation of expert count + rank per layer — higher layers want more experts), **CoMoE** ([arxiv 2506.14646](https://arxiv.org/pdf/2506.14646), [arxiv 2505.17553](https://arxiv.org/pdf/2505.17553)). Pragmatic guidance for us: **adapt expert FFN/attention projections, leave the router/gate frozen** to avoid destabilizing the 10-of-512 routing, and validate routing entropy before/after.
- **Regularization options if replay isn't enough:** **OPLoRA** (orthogonal-projection LoRA, explicitly anti-forgetting) and EWC-style consolidation ([arxiv 2510.13003](https://arxiv.org/html/2510.13003v2)). Also: **RFT/RL post-training naturally forgets less than SFT** ([arxiv 2507.05386](https://arxiv.org/html/2507.05386)) — relevant since we already have GRPO/RFT in our v1 toolkit.
- **Always early-stop on a held-out eval** (our verify-first harness IS the validation signal — use HumanEval/MBPP pass-rate, not just eval loss, as the stopping criterion).

### Bottom line for a near-saturated coder
The lift comes from **genuinely new, hard, verified data** (real-repo agentic tasks, languages/domains the base is weak in) — not from re-teaching it Python it already aces. If the heal set overlaps what it already knows, expect flat-to-negative. **Gate every checkpoint through HumanEval/MBPP + a forgetting probe.**

---

## 3. MLX LoRA/QLoRA Training Memory on 128GB Macs — Directly Actionable

### Hard constraint to know FIRST (M5 Max specific, high relevance)
There is an **open mlx-lm issue (#1206)**: LoRA training **crashes on the first backward pass on M5 Max** (`applegpu_g17s`) with `[METAL] Command buffer execution failed: Insufficient Memory` — *despite low system memory* — specifically for **Qwen3.5-9B-4bit**, while **Qwen3-8B-4bit trains fine** with identical settings ([github.com/ml-explore/mlx-lm#1206](https://github.com/ml-explore/mlx-lm/issues/1206)). This is an **architecture-specific Metal codegen bug on the newest Qwen attention + newest GPU**, not a true OOM. **Action: before any long heal run, do a 5-iteration smoke test on M5 Max with our exact Qwen3-Coder-Next build.** Our own memory note (`glm52-lora-seqlen-limit`) already flags a related DSA/index_topk scatter-VJP crash — consistent failure family. Hybrid-attention/MoE backward passes are the fragile path on this hardware.

### The five official memory escape hatches (mlx-lm `LORA.md`)
1. Quantize the base (we already run 8-bit; QLoRA off a 4-bit base saves the most).
2. Reduce **batch size** (start at 1).
3. Reduce **`--num-layers`** (only adapt top N layers — e.g. 8–16, not all 48+).
4. **Shorten sequences** (`--max-seq` / chunk examples).
5. **`--grad-checkpoint`** — trades ~30% slower training for big activation-memory savings.
([github.com/ml-explore/mlx-lm LORA.md](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/LORA.md))

### Concrete MLX memory knobs that stop Metal OOM (from production reports)
From issue #828 and field reports ([github.com/ml-explore/mlx-lm#828](https://github.com/ml-explore/mlx-lm/issues/828), [insiderllm](https://insiderllm.com/guides/fine-tuning-mac-lora-mlx/)):
```python
ws = mx.metal.device_info()["max_recommended_working_set_size"]
mx.set_wired_limit(int(ws * 0.9))      # 90% wired — stability sweet spot
mx.set_memory_limit(int(ws * 0.9))     # drop the default 1.5× multiplier
mx.set_cache_limit(int(ws * 0.45))     # halve cache; cache_limit=0 also works
```
- `cache_limit=0` reported **no crashes, ~no perf loss** — strongest single fix for "memory climbs until it dies."
- These resolved real OOMs (e.g. 48GB box where Python held 36GB).
- **Wired memory matters on Apple Silicon:** wiring too much starves the rest of the system; 90% is the reported balance.

### Our 128GB reality
- Unified memory ≈ **96GB GPU-usable** of the 128GB ([buildmvpfast](https://www.buildmvpfast.com/blog/mlx-apple-silicon-ai-development-mac-fine-tune-llm-2026)).
- 80B-A3B at 8-bit base ≈ ~80–85GB resident — **leaves little headroom for activations + optimizer + adapters.** Expect to *need* grad-checkpoint + num-layers cap + max-seq ≤2048 (our own note `glm52-lora-seqlen-limit`: heal max-seq **MUST be ≤2048** or DSA scatter-VJP crashes at step 1) + cache_limit trim. Strongly consider **QLoRA off a 4-bit base** for the heal even though we serve at 8-bit — train on 4-bit, merge/serve at 8-bit.
- Throughput anchor: a 7B at bs1/num-layers-4 ran ~250 tok/s on an M1 Max; an 80B-A3B with few adapted layers should be usable but plan in iterations, not epochs.

---

## 4. Planner + Coder / Multi-Agent Local Agentic Coding

### Does a separate planner help?
**Yes, conditionally — and it's now a standard pattern.** Aider's **architect/editor mode** (strong reasoner plans, fast/cheaper model edits) set records on Aider's own edit benchmark and is the canonical reference implementation ([aider.chat/docs/usage/modes](https://aider.chat/docs/usage/modes.html), [generaitelabs](https://generaitelabs.com/aider-implements-new-architect-editor-approach-for-ai-assisted-coding/)). The leaderboard even logs explicit architect combos (e.g. DeepSeek-R1 + Sonnet via `aider --architect`).

**When it helps (evidence-backed):**
- When the **planner is genuinely stronger at reasoning** than the editor, and the editor is reliable at applying diffs. The classic win is "reasoning model that's bad at file edits" (o1-class) + "clean editor."
- When you want to **decouple slow expensive reasoning from fast cheap editing** (cost/latency).

**When it does NOT help / can hurt:**
- If planner and editor are the **same model** (our case: Qwen3-Coder-Next planning *and* editing), the architect split mostly adds latency and an extra failure surface. The gain comes from a *capability gap* between the two roles.
- Our proposed **planner Qwen3.6-35B-A3B + coder Qwen3-Coder-Next-80B-A3B** only pays off if the 35B planner actually out-reasons the 80B coder on decomposition. That's unproven and plausibly *false* (the 80B coder was agentic-trained). **Recommendation: A/B it, don't assume it.** Measure on a held-out agentic task set with vs without the planner. Two A3B models also means doubling resident memory — confirm both fit alongside KV cache.

### Best open agentic harnesses for local MLX (June 2026)
- **mlx_lm.server → OpenAI-compatible localhost** is the universal bridge: any harness that speaks OpenAI API talks to our model with zero awareness it's local ([yuv.ai/learn/opencode-cli](https://yuv.ai/learn/opencode-cli)). This is the key integration fact for everything below.
- **OpenCode** — terminal-native, ~175K stars, 75+ providers incl. local, LSP integration, sub-agents ([opencode.ai/docs/agents](https://opencode.ai/docs/agents/)). Strong default for local MLX agentic work.
- **Aider** — deepest repo-map/edit-mode/git engineering; *the* reference for architect/editor; right for surgical edits ([digitalapplied](https://www.digitalapplied.com/blog/aider-deep-dive-cli-agentic-coding-tutorial-2026)).
- **Pi** (our harness) and **Goose** — listed among the core open CLI agent harnesses ([awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents)). Pi is a reasonable home given our verify-first integration; OpenCode/Aider are the benchmarks to beat.
- **Practical note:** all of these assume the model emits clean tool-calls / well-formed diffs. Qwen3-Coder-Next's explicit multi-format tool-call training is a real advantage here — exploit it by matching the harness's tool template to one of its 21 trained variants.

---

## 5. Verify-First / Test-Time Compute for Code

### How much lift does verify-first actually give?
- **Strong models gain LESS from best-of-N than weak ones, and the verifier is the ceiling.** Best-of-N = generate N, score with a verifier, return best; its effectiveness is **bounded by verifier precision**. With *automatic* verifiers (compile/run/tests — exactly our setup) it keeps scaling; without them it plateaus as N grows because selection can't find rare correct samples ([arxiv 2502.18581](https://arxiv.org/pdf/2502.18581)). **Our compile/run-gate is the strong case** — we have a near-perfect verifier for "does it run/pass tests."
- **Concrete, cross-checked lift number (verifier-guided TTS on SWE-bench Verified, SWE-Lego, Jan 2026):**
  - 8B: 42.2% → **49.6%** (+7.4 pts) at TTS@16
  - 32B: 52.6% → **58.8%** (+6.2 pts) at TTS@16
  ([arxiv 2601.01426](https://arxiv.org/html/2601.01426v1), corroborated [emergentmind](https://www.emergentmind.com/topics/swe-lego-dataset)). Note the lift is **larger on the weaker model** — consistent with diminishing returns at the top.
- **Our own data is a clean confirmation:** verifier-repair loop took HumanEval 93.3% → **97.6%** (+4.3 pts). That's exactly the regime: a strong model + a real verifier + a repair loop yields mid-single-digit lift, and the loop closes most remaining failures. Expect the *same shape* on harder benchmarks but a *smaller* ceiling.
- **Generative verifiers** (SWE-Lego-Verifier-8B / 30B-A3B) give *monotonic* improvement toward the pass@K upper bound — better scaling than naive self-consistency, which *converges back to the base model* as k grows for open-ended code ([arxiv 2601.01426](https://arxiv.org/html/2601.01426v1), [arxiv 2311.17311](https://arxiv.org/pdf/2311.17311)). For agentic SWE tasks where "did it run" isn't sufficient, a learned verifier beats voting.
- **SWE-Replay** ([arxiv 2601.22129](https://arxiv.org/pdf/2601.22129)) — efficient TTS specifically for SWE agents; relevant if we extend verify-first from unit-level to repo-level.

### Takeaway
Verify-first is our **highest-confidence, already-proven** lever. The marginal play is: (a) **repair loop > raw best-of-N** (we already do this), (b) add a **learned/generative verifier** for tasks where execution alone can't rank candidates, (c) on saturated unit benchmarks the headroom is small — push verify-first toward **harder, repo-level** tasks where the lift is real.

---

## What We Should Try Next (Prioritized, Tailored)

1. **[Do first — derisk] M5 Max LoRA smoke test (5–20 iters)** on our exact Qwen3-Coder-Next 8-bit *and* a 4-bit copy, with `max-seq ≤ 2048`, `--grad-checkpoint`, `--num-layers 8–16`, bs1, and the `set_wired_limit/memory_limit/cache_limit` trio above. Issue #1206 + our own DSA scatter-VJP note say the *newest Qwen attention on M5 Max can crash the backward pass regardless of memory*. Confirm it trains before planning a long run. **(Section 3)**

2. **[Highest-leverage capability gate] Stand up a real SWE-bench Verified (ideally SWE-bench Pro) local eval** with an OpenHands or mini-SWE scaffold. Our HumanEval/MBPP numbers do **not** predict agentic SWE capability. This becomes the held-out metric for everything else. **(Sections 1, 5)**

3. **[Heal recipe] Conservative anti-forgetting LoRA:** r=16, alpha=32, **LR 1e-5→5e-5**, target attention±expert-FFN proj, **freeze the MoE router/gate**, **15–20% replay** (HumanEval/MBPP-style + general instruction) mixed into the custom code data. Early-stop on **pass-rate** (via our verify harness), not loss. Reach for DoRA *only* after a measured plateau. **(Section 2)**

4. **[Data is the real lift] Make the heal set genuinely new+hard+verified** — real-repo agentic trajectories, weak-language coverage, failure cases our verifier catches — not Python it already aces. Reuse our v1 GRPO/RFT/hardneg data (RFT forgets less than SFT). Near-saturated coders only move on novel difficulty. **(Section 2)**

5. **[A/B, don't assume] Test planner(35B-A3B)+coder(80B-A3B) against coder-only** on the SWE eval from #2. Architect/editor only wins on a real capability gap; same-family A3B+A3B may just add latency + double the memory footprint. Verify both fit with KV cache before committing. **(Section 4)**

6. **[Extend the proven lever] Push verify-first from unit-level to repo-level**, and pilot a **generative/learned verifier** (SWE-Lego-Verifier-30B-A3B style) for ranking candidates where execution alone can't. Expect ~+6–7 pts on hard tasks per SWE-Lego, vs the small remaining headroom on saturated HumanEval/MBPP. **(Section 5)**

7. **[Harness] Keep mlx_lm.server as the OpenAI-compatible bridge**; benchmark Pi against OpenCode + Aider-architect on our SWE eval so we know we're not leaving free agentic wins on the table. Match the harness tool-call template to one of Qwen3-Coder-Next's 21 trained variants. **(Section 4)**

### Adversarial caveats to remember
- SWE-bench Verified is contaminated/saturated; weight **SWE-bench Pro** and our own *held-out* eval over any single leaderboard cell.
- DoRA's edge largely vanishes once LR is tuned — don't burn time on PEFT-method shopping before tuning LR.
- Best-of-N lift shrinks as the base gets stronger and is capped by verifier quality; our biggest remaining gains are on **harder** tasks, not on re-running easy ones.
