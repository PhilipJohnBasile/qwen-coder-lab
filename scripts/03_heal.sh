#!/usr/bin/env bash
# Stage 3 — LoRA-heal the clean base on the FOCUS-9 code gold.
# GPU-heavy: free the serve first (never double-load = OOM panic). max-seq ≤2048 (DSA cap).
set -euo pipefail

MODEL="${MODEL_DIR:-models/qwen3-coder-next-8bit}"
DATA="${DATA:-data/heal-focus9}"
ADAPTER="${ADAPTER:-heal/adapters-focus9}"

echo ">> freeing the serve (one GPU model resident at a time)"
pkill -9 -f "mlx_lm.server" 2>/dev/null || true; sleep 2

echo ">> LoRA heal: $MODEL  on  $DATA  -> $ADAPTER"
python -m mlx_lm lora \
  --model "$MODEL" \
  --train \
  --data "$DATA" \
  --max-seq-length 2048 \
  --num-layers 8 \
  --batch-size 1 \
  --iters "${ITERS:-300}" \
  --learning-rate 1e-5 \
  --adapter-path "$ADAPTER" \
  --steps-per-report 10 \
  --steps-per-eval 100 \
  --grad-checkpoint

echo ">> done. re-serve WITH the adapter to measure the lift:"
echo "   mlx_lm.server --model $MODEL --adapter-path $ADAPTER --port 8080"
echo "   then: python scripts/01_baseline.py --n 164   # compare to 93.3%"
