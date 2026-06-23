# Overnight run — Mon Jun 22 22:19:27 EDT 2026

Base ref: HumanEval raw 93.3% / +loop 97.6% | MBPP raw 75.4%

| Phase | Probe | Result |
|---|---|---|
| base | MBPP-500 +loop(k=4) | pass@1 = 442/500 = 88.4% |

Planner prefetch: 8.5G (for tomorrow's 2-model test)

## Stage 4 + 5 (healed model)
| Stage | Result |
|---|---|
| 4 soul(security) | probe = 4/5 pass |
| 5 agent (KVStore+pytest) | STAGE 5 UNSOLVED after 6 iters |

ANE embed: data/ane_embeddings/heal_corpus.npy
done

## HEAL RESULT — base=qwen3-coder-next-8bit seq=1024 layers=4
| Model | Probe | Result |
|---|---|---|
| HEALED | MBPP-500 raw | pass@1 = 377/500 = 75.4% |
| HEALED | HumanEval-164 raw | pass@1 = 153/164 = 93.3% |
| HEALED | soul(security) | probe = 4/5 pass |
| HEALED | agent loop | STAGE 5 UNSOLVED after 6 iters (last output above) == |
