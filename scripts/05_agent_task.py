#!/usr/bin/env python3
"""Stage 5 — a REAL agentic coding loop: read -> edit -> run pytest -> fix from the error.

Self-contained + sandboxed (a scratch repo, never touches your real code). The model is given a
multi-function module stubbed with NotImplementedError plus a real pytest suite it must make pass.
It iterates: see the failing test output -> rewrite the impl file -> re-run pytest -> repeat (≤K).
This is the honest "does it actually code through a loop", not a single-shot completion.

Usage: python scripts/05_agent_task.py [--k 6]
Drives whatever model is served on :8080 (mount the healed adapter to test the healed model).
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from importlib import import_module
b = import_module("01_baseline")  # chat / extract_code

IMPL = '''\
"""A tiny in-memory key-value store with TTL and LRU eviction. Implement the methods."""
import time


class KVStore:
    def __init__(self, capacity, clock=time.time):
        self.capacity = capacity
        self._clock = clock
        # TODO: your storage

    def set(self, key, value, ttl=None):
        """Store value. ttl (seconds) optional. Inserting beyond capacity evicts the
        least-recently-USED live key. Updating an existing key counts as a use."""
        raise NotImplementedError

    def get(self, key):
        """Return value, or None if missing or expired. A successful get is a 'use'."""
        raise NotImplementedError

    def delete(self, key):
        """Remove key. Return True if it existed (and was live), else False."""
        raise NotImplementedError

    def __len__(self):
        """Number of LIVE (non-expired) keys."""
        raise NotImplementedError
'''

TESTS = '''\
from kvstore import KVStore


class Clock:
    def __init__(self): self.t = 1000.0
    def __call__(self): return self.t
    def tick(self, dt): self.t += dt


def test_set_get():
    s = KVStore(10)
    s.set("a", 1); assert s.get("a") == 1
    assert s.get("missing") is None


def test_ttl_expiry():
    c = Clock(); s = KVStore(10, clock=c)
    s.set("a", 1, ttl=5)
    assert s.get("a") == 1
    c.tick(6)
    assert s.get("a") is None
    assert len(s) == 0


def test_lru_eviction():
    s = KVStore(2)
    s.set("a", 1); s.set("b", 2)
    assert s.get("a") == 1          # 'a' now most-recently-used
    s.set("c", 3)                   # capacity 2 -> evict LRU which is 'b'
    assert s.get("b") is None
    assert s.get("a") == 1 and s.get("c") == 3


def test_update_is_use_and_delete():
    s = KVStore(2)
    s.set("a", 1); s.set("b", 2)
    s.set("a", 10)                  # update 'a' -> 'a' most-recent
    s.set("c", 3)                   # evict LRU 'b'
    assert s.get("b") is None and s.get("a") == 10
    assert s.delete("a") is True and s.delete("a") is False


def test_len_counts_live_only():
    c = Clock(); s = KVStore(10, clock=c)
    s.set("x", 1, ttl=2); s.set("y", 2)
    assert len(s) == 2
    c.tick(3)
    assert len(s) == 1
'''


def run_pytest(d):
    p = subprocess.run([sys.executable, "-m", "pytest", "-q", "--no-header", "-x"],
                       cwd=d, capture_output=True, text=True, timeout=120)
    return p.returncode == 0, (p.stdout + p.stderr)[-1800:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--base", default=os.environ.get("BASE", "http://localhost:8080/v1"))
    ap.add_argument("--model", default=os.environ.get("MODEL", "qwen3-coder-next"))
    args = ap.parse_args()

    d = tempfile.mkdtemp(prefix="agent_task_")
    open(os.path.join(d, "kvstore.py"), "w").write(IMPL)
    open(os.path.join(d, "test_kvstore.py"), "w").write(TESTS)
    ok, out = run_pytest(d)
    print(f"sandbox: {d}\ninitial pytest pass={ok}")

    for i in range(1, args.k + 1):
        cur = open(os.path.join(d, "kvstore.py")).read()
        prompt = (
            "You are fixing a Python module so its pytest suite passes.\n\n"
            f"=== test_kvstore.py (read-only) ===\n{TESTS}\n"
            f"=== kvstore.py (EDIT THIS) ===\n{cur}\n"
            f"=== latest pytest output ===\n{out}\n\n"
            "Return the COMPLETE corrected kvstore.py in a single ```python code block.")
        try:
            code = b.extract_code(b.chat(args.base, args.model, prompt, max_tokens=2048))
        except Exception as e:
            print(f"iter {i}: gen error {e}"); continue
        if "class KVStore" not in code:           # guard against a junk reply
            print(f"iter {i}: reply missing class, skip-write"); continue
        open(os.path.join(d, "kvstore.py"), "w").write(code)
        ok, out = run_pytest(d)
        print(f"iter {i}: pytest pass={ok}")
        if ok:
            print(f"\n== STAGE 5 SOLVED in {i} iteration(s) ==")
            shutil.rmtree(d, ignore_errors=True)
            return
    print(f"\n== STAGE 5 UNSOLVED after {args.k} iters (last output above) ==")
    shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    main()
