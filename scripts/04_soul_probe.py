#!/usr/bin/env python3
"""Stage 4 — soul probe: does activating a heritage canon produce valid, working code?

Lightweight facet check. We prepend agent-toolkit's SECURITY_CANON (heritage-activation system
prompt) and ask for security-sensitive implementations, then grade each with the real python
verifier (compile + run the asserted behavior). Measures whether the healed model, soul-activated,
emits code that actually works — the swappable-soul thesis, end to end.

Usage: python scripts/04_soul_probe.py   (drives the served model on :8080)
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
TK = os.environ.get("AGENT_TOOLKIT", os.path.join(os.path.dirname(__file__), "..", "..", "agent-toolkit"))
sys.path.insert(0, os.path.abspath(TK))
from importlib import import_module
b = import_module("01_baseline")
try:
    from souls.security_canon import SECURITY_CANON
except Exception:
    SECURITY_CANON = "You are an elite security engineer; write safe, correct, hardened code."

# (prompt, harness asserting the security-correct behavior)
TASKS = [
    ("Write `def safe_eq(a: bytes, b: bytes) -> bool` doing a CONSTANT-TIME comparison of two byte "
     "strings (no early return on first mismatch).",
     "assert safe_eq(b'abc', b'abc') is True\nassert safe_eq(b'abc', b'abd') is False\n"
     "assert safe_eq(b'a', b'ab') is False\n"),
    ("Write `def hash_pw(pw: str, salt: bytes) -> bytes` using hashlib.pbkdf2_hmac sha256, "
     "100000 iters, returning the derived key.",
     "import hashlib\nk=hash_pw('pw', b'salt')\nassert k==hashlib.pbkdf2_hmac('sha256',b'pw',b'salt',100000)\n"),
    ("Write `def sanitize_path(base: str, user: str) -> str` that joins base+user but raises "
     "ValueError on any path traversal escaping base. Use os.path.realpath/commonpath.",
     "import os\nb=os.path.realpath('.')\nassert sanitize_path(b,'ok.txt').endswith('ok.txt')\n"
     "import pytest\ntry:\n sanitize_path(b,'../../etc/passwd'); assert False\nexcept ValueError: pass\n"),
    ("Write `def gen_token(n: int=32) -> str` returning a cryptographically secure URL-safe token "
     "using the secrets module.",
     "import re\nt=gen_token()\nassert len(t)>=32 and re.fullmatch(r'[A-Za-z0-9_-]+', t)\n"
     "assert gen_token()!=gen_token()\n"),
    ("Write `def escape_html(s: str) -> str` that escapes &, <, >, \" and ' to prevent XSS.",
     "assert escape_html('<a href=\"x\">&\\'') == '&lt;a href=&quot;x&quot;&gt;&amp;&#x27;'\n"),
]


def main():
    base = os.environ.get("BASE", "http://localhost:8080/v1")
    model = os.environ.get("MODEL", "qwen3-coder-next")
    sys_prompt = SECURITY_CANON
    passed = 0
    for i, (task, harness) in enumerate(TASKS):
        prompt = (f"{sys_prompt}\n\n{task}\nReturn ONLY the function in a ```python code block.")
        try:
            code = b.extract_code(b.chat(base, model, prompt, max_tokens=1024))
        except Exception as e:
            print(f"[{i}] gen-err {e}"); continue
        r = b.verify_domain("python", code, harness=harness)
        passed += bool(r.passed)
        print(f"[{i}] {'PASS' if r.passed else 'fail ' + r.stage}: {task[:48]}...")
    n = len(TASKS)
    print(f"\n== STAGE 4 soul(security) probe = {passed}/{n} pass ({100*passed/n:.0f}%) — "
          "soul-activated code that actually compiles+runs ==")


if __name__ == "__main__":
    main()
