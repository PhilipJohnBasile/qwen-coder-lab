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

## HEAL RESULT (⚠️ INVALID — server did NOT apply adapter; see CORRECTED A/B below) — base=qwen3-coder-next-8bit seq=1024 layers=4
| Model | Probe | Result |
|---|---|---|
| HEALED | MBPP-500 raw | pass@1 = 377/500 = 75.4% |
| HEALED | HumanEval-164 raw | pass@1 = 153/164 = 93.3% |
| HEALED | soul(security) | probe = 4/5 pass |
| HEALED | agent loop | STAGE 5 UNSOLVED after 6 iters (last output above) == |

## CORRECTED heal A/B (in-process, adapter verified applied)
| Model | Probe | Result |
|---|---|---|
| BASE | MBPP-500 | pass@1 = 377/500 = 75.4% |
| HEALED | MBPP-500 | pass@1 = 375/500 = 75.0% |
| BASE | HumanEval-164 | pass@1 = 153/164 = 93.3% |
| HEALED | HumanEval-164 | pass@1 = 149/164 = 90.9% |

## ✅ FINAL VERDICT (true, adapter-verified)
| Probe | Base | Healed | Δ |
|---|---|---|---|
| MBPP-500 | 75.4% | 75.0% | **−0.4 (flat)** |
| HumanEval-164 | 93.3% | 90.9% | **−2.4 (mild degrade)** |

**The LoRA heal did NOT lift the clean base — neutral on MBPP, slightly negative on HumanEval.**
Matches the research (healing a near-saturated strong coder risks mild forgetting, not gains) and the
demolition's own neutral-heal finding. The REAL wins this run: the clean base itself (93.3% HE) and the
**verify-loop** (+verify → 97.6% HE / 88.4% MBPP). Test-time compute > weight-surgery here.

GOTCHA: `mlx_lm.server --adapter-path` silently served the BASE (no adapter-load line, byte-identical
numbers). Always verify adapters via in-process `mlx_lm.load(model, adapter_path=...)` — the server
path was untrustworthy here.

## 🔒 SOULS — security facet eval (own turf, 10 headroom tasks, audited 10/10 discriminating)
| Condition | Secure/10 | Δ vs base |
|---|---|---|
| base | 60% | — |
| **+canon (prompt-soul)** | **90%** | **+30** |
| +soul (LoRA) | 70% | +10 |
| +canon+soul | 80% | +20 (LoRA *hurt* the prompt: 90→80) |

**Verdict: souls = the CANON (heritage-activation by prompting) + a facet verifier, delivered at
inference — NOT a baked LoRA adapter.** The canon cut vulns 3× unprompted; the LoRA soul was weak
alone and actively interfered with the canon. Weight-baked souls are dead; canon-as-context is alive
and beats the fine-tune. Same lesson as the rest of the project: context + verification > weight surgery.
