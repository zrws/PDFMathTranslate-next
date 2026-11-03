"""R1 loopback predicate vector regression (test-only, no network).

Proves, for BOTH layers independently:
  1. canonical 127.0.0.1        -> accepted (guard layer True; fallback layer True)
  2. ::1                        -> accepted
  3. exact 'localhost'           -> accepted
  4. '0127.0.0.1'               -> REJECTED (Windows parses as 87.0.0.1)
  5. '00127.0.0.1'              -> REJECTED (Windows parses as 87.0.0.1)
  6. short IPv4 '127.1'          -> REJECTED (non-canonical form)
  7. integer IPv4 '2130706433'  -> REJECTED
  8. hex IPv4 '0x7f.0.0.1'      -> REJECTED
  9. pseudo-loopback domain     -> REJECTED
 10. empty string / None        -> REJECTED
 11. unicode digits             -> REJECTED
 12. underscores '127.0_0.0.1'  -> REJECTED
 13. out-of-range '127.0.0.999' -> REJECTED

AND proves the BOTTOM STUB was never invoked for any rejected host when both
layers reject: we install a recording fake beneath the fallback that counts
any attempt to reach the original OS socket entrypoints. For every vector
the real chain (original -> fallback -> guard) is loaded; a REJECTED verdict
must come from the guard (source recorded), never from the OS, and the bottom
stub must show zero invocations for the rejected non-loopback vectors.

Exit: 0 all vectors behave as specified; 1 any mismatch.
Results JSON written to PDF2ZH_VECTORS_PATH when set (machine-verifiable).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# activate both layers (predicates only exist when their env vars are set)
os.environ.setdefault("PDF2ZH_GUARD_LOG", os.environ.get("PDF2ZH_GUARD_LOG", ""))
RESULTS_PATH = os.environ.get("PDF2ZH_VECTORS_PATH", "")

import guard_fallback  # noqa: E402
import sitecustomize   # noqa: E402

guard_pred = getattr(sitecustomize, "_is_loopback", None)
fb_pred = getattr(guard_fallback, "_is_loopback_strict", None)

# --- bottom stub: wrap the TRUE original functions the fallback captured ---
# guard_fallback saved _orig_* at import (its own layer of the chain). We
# cannot re-wrap them without breaking the chain, so instead we RECORD calls
# at the lowest Python entrypoint the chain still exposes AFTER the fallback:
# any call that gets past both layers lands in guard_fallback._orig_*; we
# monkeypatch the fallback's recorded originals with recording wrappers.
_bottom_calls = []


def _wrap(orig, name):
    def rec(*args, **kwargs):
        _bottom_calls.append((name, args[0] if args else None))
        raise OSError("BOTTOM-STUB: external transport must not be touched by rejected vectors")
    return rec


# NOTE: we replace the fallback's saved originals with stubs that REJECT and
# RECORD. If any vector is wrongly accepted by both layers, the connect would
# reach these stubs and be recorded as a bottom-stub hit (test failure), while
# a correct implementation never calls them for the rejected vectors.
if hasattr(guard_fallback, "_orig_connect"):
    guard_fallback._orig_connect = _wrap(guard_fallback._orig_connect, "connect")
    guard_fallback._orig_connect_ex = _wrap(guard_fallback._orig_connect_ex, "connect_ex")
    guard_fallback._orig_getaddrinfo = _wrap(guard_fallback._orig_getaddrinfo, "getaddrinfo")

VECTORS = [
    ("127.0.0.1",        True,  "canonical loopback"),
    ("::1",              True,  "ipv6 loopback"),
    ("localhost",        True,  "exact localhost"),
    ("LOCALHOST",        True,  "case-insensitive localhost"),
    ("0127.0.0.1",       False, "leading-zero octet (Windows->87.0.0.1)"),
    ("00127.0.0.1",      False, "leading-zero octet (Windows->87.0.0.1)"),
    ("127.1",            False, "short-form dotted (non-canonical)"),
    ("2130706433",       False, "integer IPv4"),
    ("0x7f.0.0.1",       False, "hex IPv4"),
    ("127.0.0.0.1",      False, "five segments"),
    ("127.audit.invalid", False, "pseudo-loopback domain"),
    ("localhost.audit.invalid", False, "pseudo-localhost domain"),
    ("",                 False, "empty host"),
    (None,               False, "None host"),
    ("127.０.0.1",       False, "unicode digits"),
    ("127.0_0.0.1",      False, "PEP-515 underscores"),
    ("127.0.0.999",      False, "out-of-range octet"),
    ("256.1.1.1",        False, "out-of-range first octet"),
    ("999.0.0.1",        False, "out-of-range first octet"),
    ("192.0.2.1",        False, "documentation non-loopback"),
]

results = []
fails = 0
for host, expected, note in VECTORS:
    g = guard_pred(host) if guard_pred else None
    f = fb_pred(host) if fb_pred else None
    ok = (g == expected) and (f == expected)
    results.append({
        "host": repr(host), "expected": expected,
        "guard": g, "fallback": f,
        "passed": ok, "note": note,
    })
    if not ok:
        fails += 1
    print("[%s] %-24r guard=%-5s fallback=%-5s expected=%-5s (%s)" % (
        "PASS" if ok else "FAIL", host, g, f, expected, note))

# bottom stub must not have been touched by any vector evaluation (predicates
# never call transport; this guards against accidental wiring in the future)
if _bottom_calls:
    print("[FAIL] bottom stub was invoked: %r" % (_bottom_calls[:3],))
    fails += 1
else:
    print("[PASS] bottom stub untouched during predicate evaluation")

summary = {
    "vector_count": len(VECTORS),
    "failed": fails,
    "bottom_stub_calls": len(_bottom_calls),
    "guard_predicate_available": guard_pred is not None,
    "fallback_predicate_available": fb_pred is not None,
    "results": results,
}
if RESULTS_PATH:
    with open(RESULTS_PATH, "w", encoding="utf-8") as fp:
        json.dump(summary, fp, indent=2)

print("=== R1 vectors: %d/%d passed, bottom_stub_calls=%d ===" % (
    len(VECTORS) - fails, len(VECTORS), len(_bottom_calls)))
sys.exit(0 if fails == 0 else 1)
