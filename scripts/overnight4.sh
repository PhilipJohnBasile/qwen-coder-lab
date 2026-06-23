#!/usr/bin/env bash
# CORRECTED heal measurement: in-process A/B (adapter guaranteed applied). Replaces the invalid
# server-path healed numbers (which silently ran the base). Base + healed, MBPP + HumanEval.
set +e
cd "$(dirname "$0")/.."
source .venv/bin/activate
LOG=/tmp/overnight; RES=RESULTS_OVERNIGHT.md
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG/driver4.log; }
pkill -9 -f "mlx_lm.server" 2>/dev/null; sleep 3

echo "" >> $RES
echo "## CORRECTED heal A/B (in-process, adapter verified applied)" >> $RES
echo "| Model | Probe | Result |" >> $RES
echo "|---|---|---|" >> $RES

say "base MBPP in-proc"; python -u scripts/bench_inproc.py --bench mbpp --n 500 > $LOG/ip_base_mbpp.log 2>&1
echo "| BASE | MBPP-500 | $(grep -o 'pass@1 = .*' $LOG/ip_base_mbpp.log | tail -1) |" >> $RES
say "healed MBPP in-proc"; python -u scripts/bench_inproc.py --bench mbpp --n 500 --adapter heal/adapters-focus9 > $LOG/ip_heal_mbpp.log 2>&1
echo "| HEALED | MBPP-500 | $(grep -o 'pass@1 = .*' $LOG/ip_heal_mbpp.log | tail -1) |" >> $RES
say "base HE in-proc"; python -u scripts/bench_inproc.py --bench he --n 164 > $LOG/ip_base_he.log 2>&1
echo "| BASE | HumanEval-164 | $(grep -o 'pass@1 = .*' $LOG/ip_base_he.log | tail -1) |" >> $RES
say "healed HE in-proc"; python -u scripts/bench_inproc.py --bench he --n 164 --adapter heal/adapters-focus9 > $LOG/ip_heal_he.log 2>&1
echo "| HEALED | HumanEval-164 | $(grep -o 'pass@1 = .*' $LOG/ip_heal_he.log | tail -1) |" >> $RES

git add -A && git -c user.name=pjb -c user.email=pbasile@basilecom.com commit -q -m "CORRECTED heal A/B: in-process bench (adapter verified applied)

The overnight server --adapter-path silently ran the base (byte-identical numbers).
This re-measures base vs healed in-process where the LoRA is provably live.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EVewhaLUJRF29rkzvEEKH9"
git push -q origin main
say "CORRECTED A/B COMPLETE — see $RES"
