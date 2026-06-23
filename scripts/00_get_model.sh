#!/usr/bin/env bash
# Pull Qwen3-Coder-Next (80B-A3B) MLX build. 8-bit ≈ 80GB, 4-bit ≈ 40GB.
# MLX only — NEVER GGUF (see head-to-head-proof-matrix note).
set -euo pipefail

QUANT="${1:-8bit}"          # 8bit | 4bit
DEST="${MODEL_DIR:-models/qwen3-coder-next-${QUANT}}"

echo ">> Fetching Qwen3-Coder-Next (${QUANT}) -> ${DEST}"
mkdir -p "$(dirname "$DEST")"

# Preferred: LM Studio's MLX channel
if command -v lms >/dev/null 2>&1; then
  echo ">> via lms (MLX)"
  lms get --mlx "Qwen3-Coder-Next" || echo "!! adjust the exact lms id if this 404s"
else
  # Fallback: hf download the mlx-community quant (adjust the exact repo id once confirmed live)
  REPO="mlx-community/Qwen3-Coder-Next-${QUANT}"
  echo ">> via hf download ${REPO}"
  hf download "$REPO" --local-dir "$DEST"
fi
echo ">> done. set MODEL_DIR=${DEST} for serve."
