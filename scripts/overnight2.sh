#!/usr/bin/env bash
# Chain AFTER overnight.sh (heal + benches). Serves the healed model, runs Stage 4 (soul) +
# Stage 5 (agent loop), records results, commits. Crash-tolerant (set +e).
set +e
cd "$(dirname "$0")/.."
source .venv/bin/activate
export MODEL="models/qwen3-coder-next-8bit"
LOG=/tmp/overnight; RES=RESULTS_OVERNIGHT.md
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG/driver2.log; }

say "waiting for overnight.sh (heal+benches) to finish..."
while pgrep -f "scripts/overnight.sh" >/dev/null 2>&1; do sleep 60; done
say "overnight.sh done — starting Stage 4 + 5"

# serve the HEALED model (adapter mounted) if it exists, else the base
ADP=""; ls heal/adapters-focus9/*.safetensors >/dev/null 2>&1 && ADP="--adapter-path heal/adapters-focus9"
pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3
nohup python -m mlx_lm server --model "$MODEL" $ADP --port 8080 > $LOG/serve2.log 2>&1 &
for i in $(seq 1 48); do curl -s -m5 http://localhost:8080/v1/models >/dev/null 2>&1 && break; sleep 5; done
say "served ($([ -n "$ADP" ] && echo healed || echo base))"

echo "" >> $RES
echo "## Stage 4 + 5 (healed model)" >> $RES
echo "| Stage | Result |" >> $RES
echo "|---|---|" >> $RES

say "Stage 4: soul(security) probe"
python -u scripts/04_soul_probe.py > $LOG/stage4.log 2>&1
echo "| 4 soul(security) | $(grep -o 'probe = .*pass' $LOG/stage4.log | tail -1) |" >> $RES

say "Stage 5: agentic read->edit->test->fix loop"
python -u scripts/05_agent_task.py --k 6 > $LOG/stage5.log 2>&1
echo "| 5 agent (KVStore+pytest) | $(grep -oE 'STAGE 5 (SOLVED in [0-9]+ iteration\(s\)|UNSOLVED after [0-9]+ iters)' $LOG/stage5.log | tail -1) |" >> $RES

pkill -9 -f "mlx_lm.server" 2>/dev/null
echo "" >> $RES
echo "ANE embed: $(ls data/ane_embeddings/heal_corpus.npy 2>/dev/null && echo done || echo skipped)" >> $RES
say "Stage 4+5 done. committing."
git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "overnight stages 4+5: soul probe + agentic loop on healed model

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EVewhaLUJRF29rkzvEEKH9"
git push -q origin main
say "ALL OVERNIGHT WORK COMPLETE — see $RES"
