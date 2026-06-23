#!/usr/bin/env bash
# Memory-safe heal with 8-bit→4-bit fallback (per research: 8-bit LoRA likely OOMs / hits mlx-lm
# #1206; 4-bit QLoRA has the headroom). Picks the first (base,seq,layers) that survives startup,
# runs the full epoch, then benches the HEALED model against a MATCHED same-base raw reference.
set +e
cd "$(dirname "$0")/.."
source .venv/bin/activate
LOG=/tmp/overnight; RES=RESULTS_OVERNIGHT.md
M8="models/qwen3-coder-next-8bit"; M4="models/qwen3-coder-next-4bit"
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG/driver3.log; }

say "waiting for base drivers (overnight.sh + overnight2.sh) to finish..."
while pgrep -f "scripts/overnight.sh" >/dev/null 2>&1 || pgrep -f "scripts/overnight2.sh" >/dev/null 2>&1; do sleep 60; done
say "base drivers done — starting heal with 8bit→4bit fallback"
pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3

# each entry: "<model> <max-seq> <num-layers>"
CONFIGS=("$M8 1024 4" "$M8 512 2" "$M4 2048 8" "$M4 1024 8" "$M4 512 4")
WBASE=""; WSEQ=""; WL=""
for cfg in "${CONFIGS[@]}"; do
  set -- $cfg; MB=$1; SEQ=$2; NL=$3
  [ -f "$MB/config.json" ] || { say "skip $MB (not downloaded)"; continue; }
  say "heal probe: base=$(basename $MB) seq=$SEQ layers=$NL (full epoch 5615)"
  : > $LOG/heal.log
  python -m mlx_lm lora --model "$MB" --train --data data/heal-focus9 \
    --max-seq-length $SEQ --num-layers $NL --batch-size 1 --iters 5615 \
    --learning-rate 1e-5 --adapter-path heal/adapters-focus9 \
    --steps-per-report 50 --steps-per-eval 1000 --save-every 200 --grad-checkpoint \
    >> $LOG/heal.log 2>&1 &
  HPID=$!; ok=0
  for s in $(seq 1 30); do
    sleep 10
    grep -qiE "Insufficient Memory|OutOfMemory|uncaught exception|Error" $LOG/heal.log && break
    grep -qE "Iter 50: Train" $LOG/heal.log && { ok=1; break; }
    kill -0 $HPID 2>/dev/null || break
  done
  if [ $ok -eq 1 ]; then WBASE=$MB; WSEQ=$SEQ; WL=$NL; say "heal RUNNING (base=$(basename $MB) seq=$SEQ L=$NL) — finishing epoch"; wait $HPID; say "heal done exit=$?"; break; fi
  say "config failed — shrinking/falling back"; kill -9 $HPID 2>/dev/null; sleep 5
done

if ! ls heal/adapters-focus9/*.safetensors >/dev/null 2>&1; then
  echo "" >> $RES; echo "**Heal: FAILED at all 8-bit AND 4-bit configs (documented).**" >> $RES
  git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "overnight: heal failed all configs (documented)"; git push -q origin main
  say "HEAL FAILED all configs"; exit 0
fi

bench(){  # $1=adapter-flag-or-empty  $2=label  -> serve, run MBPP raw + HE raw (+soul/agent if healed)
  pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3
  nohup python -m mlx_lm server --model "$WBASE" $1 --port 8080 > $LOG/serve3.log 2>&1 &
  for i in $(seq 1 48); do curl -s -m5 http://localhost:8080/v1/models >/dev/null 2>&1 && break; sleep 5; done
  export MODEL="$WBASE"
  python -u scripts/04_bench_mbpp.py --n 500 --loop 1 > $LOG/${2}_mbpp.log 2>&1
  echo "| $2 | MBPP-500 raw | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/${2}_mbpp.log | tail -1) |" >> $RES; say "$2 MBPP raw done"
  python -u scripts/01_baseline.py --n 164 > $LOG/${2}_he.log 2>&1
  echo "| $2 | HumanEval-164 raw | $(grep -o 'pass@1 = [0-9/]* = [0-9.]*%' $LOG/${2}_he.log | tail -1) |" >> $RES; say "$2 HE raw done"
  if [ "$2" = "HEALED" ]; then
    python -u scripts/04_soul_probe.py > $LOG/heal_soul.log 2>&1
    echo "| HEALED | soul(security) | $(grep -o 'probe = .*pass' $LOG/heal_soul.log | tail -1) |" >> $RES; say "healed soul done"
    python -u scripts/05_agent_task.py --k 6 > $LOG/heal_agent.log 2>&1
    echo "| HEALED | agent loop | $(grep -oE 'STAGE 5 (SOLVED in [0-9]+ iteration\(s\)|UNSOLVED.*)' $LOG/heal_agent.log | tail -1) |" >> $RES; say "healed agent done"
  fi
}

echo "" >> $RES
echo "## HEAL RESULT — base=$(basename $WBASE) seq=$WSEQ layers=$WL" >> $RES
echo "| Model | Probe | Result |" >> $RES
echo "|---|---|---|" >> $RES
# matched reference: reuse existing 8-bit numbers, else measure the 4-bit base raw
if [ "$WBASE" = "$M4" ]; then say "measuring matched 4-bit base reference"; bench "" "base-4bit"; fi
say "benching HEALED model"; bench "--adapter-path heal/adapters-focus9" "HEALED"

pkill -9 -f "mlx_lm.server" 2>/dev/null
git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "overnight: heal ($(basename $WBASE) seq=$WSEQ L=$WL) + matched before/after measurement

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EVewhaLUJRF29rkzvEEKH9"
git push -q origin main
say "HEAL ARM COMPLETE — see $RES"
