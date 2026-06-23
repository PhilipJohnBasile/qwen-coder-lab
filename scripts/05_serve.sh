#!/usr/bin/env bash
# Serve the base on :8080. ONE model resident — never double-load (MLX OOM = panic).
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-models/qwen3-coder-next-8bit}"
PORT="${PORT:-8080}"

echo ">> cleaning stale mlx procs (avoid double-load contention)"
pkill -9 -f "mlx_lm.server" 2>/dev/null || true

echo ">> serving ${MODEL_DIR} on :${PORT}"
exec mlx_lm.server \
  --model "$MODEL_DIR" \
  --port "$PORT" \
  --trust-remote-code
# add  --adapter-path heal/adapters-focus9  once Stage 3 has trained one.
