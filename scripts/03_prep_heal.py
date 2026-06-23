#!/usr/bin/env python3
"""Stage 3 prep — combine the code-relevant FOCUS-9 heal facets into one mlx_lm-lora
data dir (train.jsonl / valid.jsonl), filtered to fit the DSA seq cap.

The HF dataset ships per-facet dirs (heal/_q_agentic, _q_fullstack, ...), each chat-format
{"messages":[...]}. mlx_lm.lora wants ONE dir with train.jsonl + valid.jsonl. We merge the
code facets, drop examples whose rendered length would blow past max-seq (≤2048 — DSA index_topk
scatter-VJP crashes above that during LoRA), and shuffle deterministically.

Usage: python scripts/03_prep_heal.py [--max-chars 7000]
Then:  bash scripts/03_heal.sh
"""
import argparse, glob, json, os

# code-relevant facets for a FOCUS-9 coder heal (skip perfumery/science/lean/sound — off-target)
FACETS = ["agentic", "fullstack", "gamedev", "legacy", "repair", "factory", "security", "soulv4"]
SRC = "data/heal-data/heal"
DST = "data/heal-focus9"


def render_len(ex):
    return sum(len(m.get("content", "")) for m in ex.get("messages", []))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-chars", type=int, default=7000,
                    help="~chars ceiling (rough proxy for ≤2048 tokens) to dodge the DSA crash")
    args = ap.parse_args()
    os.makedirs(DST, exist_ok=True)

    for split in ("train", "valid"):
        rows, kept, dropped = [], 0, 0
        for facet in FACETS:
            for path in glob.glob(f"{SRC}/_q_{facet}/{split}.jsonl") + \
                        glob.glob(f"{SRC}/{facet}/{split}.jsonl"):
                for line in open(path):
                    line = line.strip()
                    if not line:
                        continue
                    ex = json.loads(line)
                    if "messages" not in ex:
                        continue
                    if render_len(ex) > args.max_chars:
                        dropped += 1; continue
                    rows.append(ex); kept += 1
        # deterministic shuffle (no Math.random equiv needed — stable interleave by index hash)
        rows.sort(key=lambda e: hash(json.dumps(e, sort_keys=True)) & 0xffffffff)
        out = f"{DST}/{split}.jsonl"
        with open(out, "w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        print(f"{split}: kept {kept}, dropped {dropped} (>{args.max_chars} chars) -> {out}")


if __name__ == "__main__":
    main()
