# RESULTS — the running scoreboard

One honest measured number per stage. Fill as each lands. Never fake it.

| Stage | Config | Metric | Number | Date |
|---|---|---|---|---|
| ref | Demolished GLM-5.2 q4a4 | HumanEval-164 pass@1 | **69.0%** | 2026-06 (prior) |
| 0 | Qwen3-Coder-Next 80B-A3B MLX 8-bit | loads + serves | ✅ 79 GB, fast (3B active) | 2026-06-22 |
| 1 | + raw single-shot | HumanEval-164 pass@1 | **93.3% (153/164)** ⬆ +24 vs 69% | 2026-06-22 |
| 2 | + verify-loop best-of-N (k=4) | HumanEval-164 pass@1 | _pending_ | |
| 3 | + FOCUS-9 LoRA heal | HumanEval-164 / FOCUS-9 probe | _pending_ | |
| 4 | + one soul (canon) | facet probe | _pending_ | |
| 5 | Pi on real repo task | solved Y/N | _pending_ | |

## Notes / observations
- **2026-06-22 — Stage 1 result: 93.3% (153/164), +24pts over the demolished 69%.** Single-shot,
  enable_thinking=false, verifier-scored (compile+run hidden tests). 11 fails: 2 compile, 9 run.
  Thesis confirmed: a clean right-sized base (Qwen3-Coder-Next 80B-A3B, 8-bit, 79 GB) far exceeds
  the demolished 744B→98GB GLM-5.2 — and runs fast (3B active). The demolition was at its ceiling;
  this isn't.
- Next: Stage 2 (verify-loop best-of-N) should claw back some of the 11 fails for near-zero cost.
