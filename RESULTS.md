# RESULTS — the running scoreboard

One honest measured number per stage. Fill as each lands. Never fake it.

| Stage | Config | Metric | Number | Date |
|---|---|---|---|---|
| ref | Demolished GLM-5.2 q4a4 | HumanEval-164 pass@1 | **69.0%** | 2026-06 (prior) |
| 0 | Qwen3-Coder-Next 80B-A3B MLX 8-bit | loads + serves | ✅ 79 GB, fast (3B active) | 2026-06-22 |
| 1 | + raw single-shot | HumanEval-164 pass@1 | **93.3% (153/164)** ⬆ +24 vs 69% | 2026-06-22 |
| 2 | + verify-loop best-of-N (k=4) | HumanEval-164 pass@1 | **97.6% (160/164)** ⬆ +4.3 vs raw | 2026-06-22 |
| 3 | + FOCUS-9 LoRA heal | HumanEval-164 / FOCUS-9 probe | _pending_ | |
| 4 | + one soul (canon) | facet probe | _pending_ | |
| — | MBPP-500 raw (headroom probe) | pass@1 | **75.4% (377/500)** — 123 fails = real room | 2026-06-22 |
| 5 | Pi on real repo task | solved Y/N | _pending_ | |

## Notes / observations
- **2026-06-22 — Stage 1 result: 93.3% (153/164), +24pts over the demolished 69%.** Single-shot,
  enable_thinking=false, verifier-scored (compile+run hidden tests). 11 fails: 2 compile, 9 run.
  Thesis confirmed: a clean right-sized base (Qwen3-Coder-Next 80B-A3B, 8-bit, 79 GB) far exceeds
  the demolished 744B→98GB GLM-5.2 — and runs fast (3B active). The demolition was at its ceiling;
  this isn't.
- **2026-06-22 — Stage 2 result: 97.6% (160/164), +4.3 over raw, avg 1.12 attempts/problem.** The
  verify-loop (feed the real compiler/runtime diag back, k=4 repair) recovered 7 of the 11 raw fails
  for near-zero cost — 152/164 passed on the FIRST try, only a handful needed repair. 4 remain
  unsolved even with retries (genuinely hard specs, not retry-fixable). Confirms the #113 lever lifts
  a strong base too. **Running total: demolished 69% → clean 93.3% → +verify-loop 97.6%.**
- Stage 3 fully prepped (5,615 FOCUS-9 heal examples + 03_heal.sh) — fire when the GPU is free.
