#!/usr/bin/env bash
# Memory-safe heal (auto-shrinking config so it can't OOM-fail) + healed-model benches.
# Runs AFTER the base-benchmark drivers finish (sequential GPU use, never double-load).
set +e
cd "$(dirname "$0")/.."
source .venv/bin/activate
export MODEL="models/qwen3-coder-next-8bit"
LOG=/tmp/overnight; RES=RESULTS_OVERNIGHT.md
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG/driver3.log; }

say "waiting for base drivers (overnight.sh + overnight2.sh) to finish..."
while pgrep -f "scripts/overnight.sh" >/dev/null 2>&1 || pgrep -f "scripts/overnight2.sh" >/dev/null 2>&1; do sleep 60; done
say "base drivers done — starting memory-safe heal"
pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3

# Try progressively smaller (seq num-layers) until one survives past startup without OOM.
CONFIGS=("1024 4" "768 4" "512 2" "384 2")
CHOSEN=""
for cfg in "${CONFIGS[@]}"; do
  SEQ=${cfg% *}; NL=${cfg#* }
  say "heal probe: max-seq=$SEQ num-layers=$NL (full epoch 5615, save-every 200)"
  : > $LOG/heal.log
  python -m mlx_lm lora --model "$MODEL" --train --data data/heal-focus9 \
    --max-seq-length $SEQ --num-layers $NL --batch-size 1 --iters 5615 \
    --learning-rate 1e-5 --adapter-path heal/adapters-focus9 \
    --steps-per-report 50 --steps-per-eval 1000 --save-every 200 --grad-checkpoint \
    >> $LOG/heal.log 2>&1 &
  HPID=$!
  # watch ~4 min: success = a Train report appears; failure = OOM or proc death
  ok=0
  for s in $(seq 1 24); do
    sleep 10
    if grep -qiE "Insufficient Memory|OutOfMemory|uncaught exception" $LOG/heal.log; then break; fi
    if grep -qE "Iter 50: Train" $LOG/heal.log; then ok=1; break; fi
    kill -0 $HPID 2>/dev/null || break
  done
  if [ $ok -eq 1 ]; then CHOSEN="$cfg"; say "heal RUNNING at seq=$SEQ L=$NL — letting full epoch complete"; wait $HPID; say "heal finished exit=$?"; break; fi
  say "config $cfg failed (OOM/early-death) — shrinking"; kill -9 $HPID 2>/dev/null; sleep 5
done

if ! ls heal/adapters-focus9/*.safetensors >/dev/null 2>&1; then
  say "HEAL FAILED at all configs — recording and exiting"
  echo "" >> $RES; echo "**Heal: FAILED (OOM at all configs) — 8-bit base too large to LoRA-train in headroom.**" >> $RES
  git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "overnight: heal OOM at all configs (documented)"; git push -q origin main
  exit 0
fi

say "serving HEALED model + benching"
pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3
nohup python -m mlx_lm server --model "$MODEL" --adapter-path heal/adapters-focus9 --port 8080 > $LOG/serve3.log 2>&1 &
for i in $(seq 1 48); do curl -s -m5 http://localhost:8080/v1/models >/dev/null 2>&1 && break; sleep 5; done

echo "" >> $RES
echo "## HEALED model ($CHOSEN config)" >> $RES
echo "| Probe | Result | vs base |" >> $RES
echo "|---|---|---|" >> $RES
python -u scripts/04_bench_mbpp.py --n 500 --loop 1 > $LOG/heal_mbpp.log 2>&1
echo "| MBPP-500 raw | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/heal_mbpp.log | tail -1) | base 75.4% |" >> $RES; say "healed MBPP raw done"
python -u scripts/01_baseline.py --n 164 > $LOG/heal_he.log 2>&1
echo "| HumanEval-164 raw | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/heal_he.log | tail -1) | base 93.3% |" >> $RES; say "healed HumanEval raw done"
python -u scripts/04_soul_probe.py > $LOG/heal_soul.log 2>&1
echo "| soul(security) | $(grep -o 'probe = .*pass' $LOG/heal_soul.log | tail -1) | - |" >> $RES; say "healed soul done"
python -u scripts/05_agent_task.py --k 6 > $LOG/heal_agent.log 2>&1
echo "| agent loop | $(grep -oE 'STAGE 5 (SOLVED in [0-9]+ iteration\(s\)|UNSOLVED.*)' $LOG/heal_agent.log | tail -1) | - |" >> $RES; say "healed agent done"

pkill -9 -f "mlx_lm.server" 2>/dev/null
git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "overnight: memory-safe heal ($CHOSEN) + full healed-model measurement

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EVewhaLUJRF29rkzvEEKH9"
git push -q origin main
say "HEAL ARM COMPLETE — see $RES"
