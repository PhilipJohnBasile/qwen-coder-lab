#!/usr/bin/env bash
# Overnight driver — "sleep on it" full-epoch heal + full before/after measurement.
# Crash-safe: checkpoints every 200 iters; each phase logged; partial results survive.
# Never double-loads a big model (one resident at a time).
set +e  # keep going even if a phase fails — we want partial results by morning
cd "$(dirname "$0")/.."
source .venv/bin/activate
export MODEL="models/qwen3-coder-next-8bit"
LOG=/tmp/overnight ; mkdir -p $LOG
RES=RESULTS_OVERNIGHT.md
stamp(){ date "+%H:%M:%S"; }
say(){ echo "[$(stamp)] $*" | tee -a $LOG/driver.log; }

wait_serve(){  # poll until the server answers, up to ~4 min
  for i in $(seq 1 48); do
    curl -s -m 5 http://localhost:8080/v1/models >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}
serve(){  # serve base, optionally with adapter ($1 = adapter path or empty)
  pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3
  if [ -n "$1" ]; then
    nohup python -m mlx_lm server --model "$MODEL" --adapter-path "$1" --port 8080 > $LOG/serve.log 2>&1 &
  else
    nohup python -m mlx_lm server --model "$MODEL" --port 8080 > $LOG/serve.log 2>&1 &
  fi
  wait_serve
}

echo "# Overnight run — $(date)" > $RES
echo "" >> $RES
echo "Base ref: HumanEval raw 93.3% / +loop 97.6% | MBPP raw 75.4%" >> $RES
echo "" >> $RES
echo "| Phase | Probe | Result |" >> $RES
echo "|---|---|---|" >> $RES

# --- Phase 0: pre-fetch the planner model for tomorrow's 2-model option (network only) ---
say "Phase 0: background-fetch planner Qwen3.6-35B-A3B 4bit (network, no GPU)"
nohup hf download mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit --local-dir models/qwen3.6-35b-a3b-4bit > $LOG/planner_dl.log 2>&1 &

# --- Phase 1: FULL-EPOCH heal (all 5615 examples, batch 1) ---
say "Phase 1: HEAL full epoch (5615 iters, save-every 200)"
pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3
python -m mlx_lm lora --model "$MODEL" --train --data data/heal-focus9 \
  --max-seq-length 2048 --num-layers 8 --batch-size 1 --iters 5615 \
  --learning-rate 1e-5 --adapter-path heal/adapters-focus9 \
  --steps-per-report 50 --steps-per-eval 500 --save-every 200 --grad-checkpoint \
  > $LOG/heal.log 2>&1
say "heal exit=$? ; adapter files: $(ls heal/adapters-focus9/*.safetensors 2>/dev/null | wc -l | tr -d ' ')"

# --- Phase 2: bench the HEALED model (raw + verify-loop) ---
if ls heal/adapters-focus9/*.safetensors >/dev/null 2>&1; then
  say "Phase 2: serve WITH adapter + bench healed"
  if serve heal/adapters-focus9; then
    python -u scripts/04_bench_mbpp.py --n 500 --loop 1 > $LOG/heal_mbpp_raw.log 2>&1
    echo "| heal | MBPP-500 raw | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/heal_mbpp_raw.log | tail -1) |" >> $RES
    say "  healed MBPP raw done"
    python -u scripts/01_baseline.py --n 164 > $LOG/heal_he_raw.log 2>&1
    echo "| heal | HumanEval-164 raw | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/heal_he_raw.log | tail -1) |" >> $RES
    say "  healed HumanEval raw done"
    python -u scripts/04_bench_mbpp.py --n 500 --loop 4 > $LOG/heal_mbpp_loop.log 2>&1
    echo "| heal | MBPP-500 +loop(k=4) | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/heal_mbpp_loop.log | tail -1) |" >> $RES
    say "  healed MBPP +loop done"
  else
    say "  serve-with-adapter FAILED to come up"
  fi
else
  say "Phase 2 SKIPPED — no adapter produced"
fi

# --- Phase 3: the missing base cell — MBPP +verify-loop on the clean base (for the 2x2) ---
say "Phase 3: serve BASE + MBPP +loop (the missing baseline cell)"
if serve ""; then
  python -u scripts/04_bench_mbpp.py --n 500 --loop 4 > $LOG/base_mbpp_loop.log 2>&1
  echo "| base | MBPP-500 +loop(k=4) | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/base_mbpp_loop.log | tail -1) |" >> $RES
  say "  base MBPP +loop done"
fi

# --- wrap up ---
pkill -9 -f "mlx_lm.server" 2>/dev/null
echo "" >> $RES
echo "Planner prefetch: $(du -sh models/qwen3.6-35b-a3b-4bit 2>/dev/null | cut -f1) (for tomorrow's 2-model test)" >> $RES
say "ALL DONE. summary in $RES"
git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "overnight: full-epoch heal + before/after 2x2 (MBPP/HumanEval, raw/loop)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EVewhaLUJRF29rkzvEEKH9" && git push -q origin main
say "pushed."
