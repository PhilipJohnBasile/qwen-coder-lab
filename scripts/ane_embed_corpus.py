#!/usr/bin/env python3
"""Use the ANE/Apple-NL on-device embedder (NOT the GPU) to embed the heal corpus + bench
fail-cases, so we can later find which training examples sit nearest the failures. Runs
concurrently with the GPU heal — keeps the Neural Engine busy instead of idle.

Best-effort: if the NL framework / asset isn't available, it logs and exits 0 (never blocks).
"""
import glob, json, os, sys

OUT = "data/ane_embeddings"


def get_embedder():
    import NaturalLanguage as NL
    emb = NL.NLEmbedding.sentenceEmbeddingForLanguage_("en")
    if emb is None:
        raise RuntimeError("NLEmbedding sentence embedding unavailable for 'en'")
    return emb


def main():
    os.makedirs(OUT, exist_ok=True)
    try:
        emb = get_embedder()
    except Exception as e:
        print(f"[ANE] embedder unavailable ({e}) — skipping cleanly"); return
    import numpy as np

    # corpus: first user turn of each heal example
    texts, meta = [], []
    for path in sorted(glob.glob("data/heal-focus9/train.jsonl")):
        for j, line in enumerate(open(path)):
            line = line.strip()
            if not line:
                continue
            t = json.loads(line).get("text", "")
            # grab the user content between the first im_start user and im_end
            seg = t.split("<|im_start|>")
            user = next((s for s in seg if s.startswith("user")), "")
            user = user[:600].replace("user\n", "", 1)
            if user:
                texts.append(user); meta.append({"src": path, "i": j})
            if len(texts) >= 4000:
                break

    vecs, kept = [], []
    for k, t in enumerate(texts):
        v = emb.vectorForString_(t)
        if v is None:
            continue
        vecs.append(list(v)); kept.append(meta[k])
        if k % 500 == 0:
            print(f"[ANE] embedded {k}/{len(texts)} on the Neural Engine...")
    if not vecs:
        print("[ANE] no vectors produced — skipping"); return
    arr = np.array(vecs, dtype="float32")
    np.save(f"{OUT}/heal_corpus.npy", arr)
    json.dump(kept, open(f"{OUT}/heal_corpus_meta.json", "w"))
    print(f"[ANE] DONE — {arr.shape[0]} heal examples embedded ({arr.shape[1]}-d) on ANE -> {OUT}/")


if __name__ == "__main__":
    main()
