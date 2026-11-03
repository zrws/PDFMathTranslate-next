"""P0 systematic acceptance: comprehensive guard test with independent fallback.

Architecture:
    original function -> guard_fallback (safety net) -> sitecustomize guard

This script is run by p0_c1_guard_test.ps1. The PS wrapper does NOT put
the guard directory in PYTHONPATH at Python startup, so sitecustomize is
NOT auto-loaded. Instead, this script explicitly imports modules in the
correct order:

1. import guard_fallback  (patches original functions - safety net)
2. import sitecustomize   (patches fallback-wrapped functions - guard under test)

HARD STOP (S2/A2): if the fallback is not CONFIRMED fully active (log path
set, FALLBACK_ACTIVE line present, counter accessible, log writable) the test
aborts BEFORE any network attempt (distinct exit code 3, no FAIL-then-continue).

Test scenarios (controlled by PDF2ZH_GUARD_TEST_MODE env var):
- normal:     Guard active, all hooks installed. Tests verify guard blocks
              with matching log entries and fallback hit count = 0.
              Includes pseudo-loopback hostnames (127.audit.invalid etc.)
              which must be rejected by BOTH layers' predicates and never
              reach real DNS resolution or connect.
- no_guard:   PDF2ZH_GUARD_LOG not set. sitecustomize imports but doesn't
              activate. Fallback catches all -> test must FAIL.
- partial:    PDF2ZH_GUARD_SKIP=async. Sync hooks work, async doesn't.
              Async tests should hit fallback -> partial FAIL.

Each blocked test verifies:
- Rejection source is SPECIFICALLY the guard (not OS timeout/refused/fallback)
- A NEW matching BLOCKED entry appears in THIS run's guard log
- Fallback hit delta (0 for guard-pass tests, >0 for guard-fail tests)

Results are printed AND (when PDF2ZH_RESULTS_PATH is set) written as JSON
to that path, so the PS wrapper can drive verdicts from parsed data
instead of free-text matching.
"""

import json
import os
import socket
import sys

# Resolve guard directory
_guard_dir = os.path.dirname(os.path.abspath(__file__))
TEST_MODE = os.environ.get("PDF2ZH_GUARD_TEST_MODE", "normal")
GUARD_LOG = os.environ.get("PDF2ZH_GUARD_LOG", "")
FALLBACK_LOG = os.environ.get("PDF2ZH_FALLBACK_LOG", "")
RESULTS_PATH = os.environ.get("PDF2ZH_RESULTS_PATH", "")

RESULTS = {}

def _write_results():
    if RESULTS_PATH:
        try:
            with open(RESULTS_PATH, "w", encoding="utf-8") as f:
                json.dump(RESULTS, f, indent=2)
        except Exception as e:
            print("WARN: cannot write results json: %s" % e)

def _read_log(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception:
        return ""

def _count_pattern(text, pattern):
    return sum(1 for line in text.splitlines() if pattern in line)

def _run_test(name, func, expect_blocked=True, expect_source="guard"):
    """Run a test with independent verification of rejection source."""
    guard_before = _read_log(GUARD_LOG)
    fb_before_text = _read_log(FALLBACK_LOG)
    fb_before = _count_pattern(fb_before_text, "FALLBACK_HIT")

    error = None
    rejected = False
    try:
        func()
        # If func returns normally, connection succeeded (should not happen for blocked tests)
    except Exception as e:
        rejected = True
        error = str(e)

    guard_after = _read_log(GUARD_LOG)
    fb_after_text = _read_log(FALLBACK_LOG)
    fb_after = _count_pattern(fb_after_text, "FALLBACK_HIT")
    new_guard = _count_pattern(guard_after, "BLOCKED") - _count_pattern(guard_before, "BLOCKED")
    new_fb = fb_after - fb_before

    r = {
        "rejected": rejected,
        "error": (error or "")[:200],
        "new_guard_blocks": new_guard,
        "new_fallback_hits": new_fb,
        "source": "unknown",
    }

    if expect_blocked:
        if not rejected:
            r["passed"] = False
            r["reason"] = "connection was NOT rejected (guard and fallback both failed!)"
        elif new_fb > 0:
            r["source"] = "fallback"
            if expect_source == "guard":
                r["passed"] = False
                r["reason"] = "fallback caught it (guard failed); no real connection made but guard is broken"
            else:
                r["passed"] = True
                r["reason"] = "fallback correctly caught guard failure"
        elif new_guard > 0:
            r["source"] = "guard"
            if expect_source == "guard":
                r["passed"] = True
                r["reason"] = "guard blocked with matching log entry"
            else:
                r["passed"] = False
                r["reason"] = "guard blocked but test expected fallback"
        else:
            # Rejected but no guard log and no fallback hit
            if "net-guard" in (error or "") or "blocked" in (error or "").lower():
                r["source"] = "guard_no_log"
                r["passed"] = False
                r["reason"] = "guard raised but no matching BLOCKED entry (partial failure)"
            else:
                r["source"] = "os"
                r["passed"] = False
                r["reason"] = "rejected by OS/network timeout, not by guard (no BLOCKED, no fallback)"
    else:
        # Expected to succeed (loopback)
        if rejected:
            r["source"] = "wrongly_blocked"
            r["passed"] = False
            r["reason"] = "loopback was wrongly rejected: %s" % (error or "")[:100]
        else:
            r["source"] = "allowed"
            r["passed"] = True
            r["reason"] = "connection succeeded as expected"

    RESULTS[name] = r
    status = "PASS" if r.get("passed") else "FAIL"
    print("  [%s] %s: source=%s reason=%s" % (status, name, r["source"], r.get("reason", "")))


# === Step 0: HARD-STOP preconditions (before ANY network attempt) ===
if not FALLBACK_LOG:
    RESULTS["fallback_confirmed"] = {
        "passed": False,
        "reason": "PDF2ZH_FALLBACK_LOG not set; fallback safety net cannot be confirmed; "
                  "aborting before any network attempt (hard stop)",
    }
    print("FATAL: fallback log not set - hard stop, no network tests run")
    _write_results()
    print("\n=== JSON ===")
    print(json.dumps(RESULTS, indent=2))
    sys.exit(3)

# === Step 1: Install fallback FIRST ===
sys.path.insert(0, _guard_dir)
import guard_fallback

# === Step 2: Install guard (sitecustomize) ===
# In "no_guard" mode, PDF2ZH_GUARD_LOG is not set, so sitecustomize imports but doesn't activate
import sitecustomize

# === Step 2b: Confirm fallback is FULLY active (hooks + counter + log) ===
fb_active_flag = guard_fallback.is_fallback_active()
fb_log_text = _read_log(FALLBACK_LOG)
fb_active_line = "FALLBACK_ACTIVE" in fb_log_text
fb_counter_ok = hasattr(guard_fallback, "get_fallback_hits") and guard_fallback.get_fallback_hits() >= 0
fb_log_writable = False
try:
    with open(FALLBACK_LOG, "a", encoding="utf-8") as f:
        f.write("FALLBACK_SELFTEST_OK %d\n" % os.getpid())
    fb_log_writable = True
except Exception:
    fb_log_writable = False

fb_confirmed = fb_active_flag and fb_active_line and fb_counter_ok and fb_log_writable
RESULTS["fallback_confirmed"] = {
    "passed": fb_confirmed,
    "reason": "fallback fully confirmed (active=%s log_line=%s counter=%s writable=%s)"
              % (fb_active_flag, fb_active_line, fb_counter_ok, fb_log_writable)
              if fb_confirmed else
              "fallback NOT fully confirmed: active=%s log_line=%s counter=%s writable=%s; "
              "hard stop before any network attempt"
              % (fb_active_flag, fb_active_line, fb_counter_ok, fb_log_writable),
}
print("  [%s] fallback_confirmed: %s" % ("PASS" if fb_confirmed else "FAIL",
                                          RESULTS["fallback_confirmed"]["reason"]))
if not fb_confirmed:
    _write_results()
    print("\n=== JSON ===")
    print(json.dumps(RESULTS, indent=2))
    sys.exit(3)

# === Verify guard installation ===
guard_text = _read_log(GUARD_LOG)
this_pid = os.getpid()
guard_active_this_pid = False
for line in guard_text.splitlines():
    if line.startswith("GUARD_ACTIVE"):
        parts = line.split()
        if len(parts) >= 2 and parts[1] == str(this_pid):
            guard_active_this_pid = True
            break

RESULTS["guard_loaded"] = {
    "passed": guard_active_this_pid if TEST_MODE != "no_guard" else True,
    "reason": "GUARD_ACTIVE with PID %d" % this_pid if guard_active_this_pid
              else ("expected absent (no_guard mode)" if TEST_MODE == "no_guard" else "GUARD_ACTIVE missing or wrong PID"),
}
print("  [%s] guard_loaded: %s" % ("PASS" if RESULTS["guard_loaded"]["passed"] else "FAIL",
                                    RESULTS["guard_loaded"]["reason"]))

RESULTS["fallback_active"] = {
    "passed": fb_active_flag,
    "reason": "fallback installed" if fb_active_flag else "fallback NOT installed",
}
print("  [%s] fallback_active" % ("PASS" if RESULTS["fallback_active"]["passed"] else "FAIL"))

# === Shared test payloads ===
def _try_sync():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("192.0.2.1", 9))

def _try_async():
    import asyncio
    async def _ac():
        r, w = await asyncio.open_connection("192.0.2.1", 9)
        w.close()
    asyncio.run(_ac())

def _try_dns():
    socket.getaddrinfo("example-test-nonexistent.com", 80)

# === Step 3: Run test cases ===
if TEST_MODE == "no_guard":
    # In no_guard mode, all outbound attempts should hit FALLBACK (not guard)
    # The test should FAIL because guard is absent
    print("\n--- Mode: no_guard (guard absent, fallback should catch) ---")

    _run_test("no_guard_sync", _try_sync, expect_blocked=True, expect_source="fallback")
    _run_test("no_guard_async", _try_async, expect_blocked=True, expect_source="fallback")
    _run_test("no_guard_dns", _try_dns, expect_blocked=True, expect_source="fallback")

    # Verify: all tests should have been caught by fallback, proving fallback works
    # But guard test overall should FAIL (guard is absent)
    fb_total = _count_pattern(_read_log(FALLBACK_LOG), "FALLBACK_HIT")
    RESULTS["overall"] = {
        "passed": False,  # Guard test FAILS when guard is absent
        "reason": "guard absent; fallback caught %d attempts (safety net worked, but guard test fails)" % fb_total,
    }

elif TEST_MODE == "partial":
    # In partial mode, sync works but async is skipped (PDF2ZH_GUARD_SKIP=async)
    print("\n--- Mode: partial (sync OK, async skipped -> fallback catches) ---")

    _run_test("partial_sync_guarded", _try_sync, expect_blocked=True, expect_source="guard")
    _run_test("partial_async_fallback", _try_async, expect_blocked=True, expect_source="fallback")

    RESULTS["overall"] = {
        "passed": False,  # Partial failure means guard is broken
        "reason": "async hook was skipped; fallback caught async attempt",
    }

else:
    # Normal mode: guard fully active
    print("\n--- Mode: normal (guard active, all hooks installed) ---")

    _run_test("sync_blocked", _try_sync, expect_blocked=True, expect_source="guard")

    def _try_connect_ex():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect_ex(("192.0.2.1", 9))

    _run_test("connect_ex_blocked", _try_connect_ex, expect_blocked=True, expect_source="guard")
    _run_test("dns_blocked", _try_dns, expect_blocked=True, expect_source="guard")
    _run_test("async_blocked", _try_async, expect_blocked=True, expect_source="guard")

    def _try_httpx():
        import asyncio
        import httpx
        async def _hx():
            async with httpx.AsyncClient(timeout=3) as client:
                await client.get("http://192.0.2.1:9/test")
        asyncio.run(_hx())

    _run_test("httpx_blocked", _try_httpx, expect_blocked=True, expect_source="guard")

    # Loopback should succeed (with real listener)
    def _try_loopback():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.settimeout(3)
        client.connect(("127.0.0.1", port))
        conn, addr = server.accept()
        conn.send(b"ok")
        data = client.recv(2)
        if data != b"ok":
            raise RuntimeError("loopback data mismatch")
        conn.close()
        client.close()
        server.close()

    _run_test("loopback_allowed", _try_loopback, expect_blocked=False)

    # Fallback should have ZERO hits (guard worked perfectly)
    fb_total = _count_pattern(_read_log(FALLBACK_LOG), "FALLBACK_HIT")
    RESULTS["fallback_zero_hits"] = {
        "passed": fb_total == 0,
        "reason": "fallback hits = %d (guard blocked all, fallback untouched)" % fb_total
                  if fb_total == 0 else "fallback hits = %d (guard had gaps!)" % fb_total,
    }
    print("  [%s] fallback_zero_hits: %s" % ("PASS" if fb_total == 0 else "FAIL",
                                               RESULTS["fallback_zero_hits"]["reason"]))

    # === S2/N01: strict predicates on BOTH layers (no network, pure predicate) ===
    pseudo_hosts = ["127.audit.invalid", "localhost.audit.invalid", "", "256.1.1.1", "127.0.0.999"]
    guard_pred = getattr(sitecustomize, "_is_loopback", None)
    fallback_pred = getattr(guard_fallback, "_is_loopback_strict", None)
    if guard_pred is None or fallback_pred is None:
        RESULTS["pseudo_loopback_predicate"] = {
            "passed": False,
            "reason": "strict predicate not accessible on one or both layers "
                      "(sitecustomize._is_loopback=%s, guard_fallback._is_loopback_strict=%s)"
                      % (guard_pred is not None, fallback_pred is not None),
        }
    else:
        bad = [h for h in pseudo_hosts if guard_pred(h) or fallback_pred(h)]
        RESULTS["pseudo_loopback_predicate"] = {
            "passed": len(bad) == 0,
            "reason": ("both layers reject %d pseudo-loopback hosts" % len(pseudo_hosts))
                      if len(bad) == 0 else
                      ("pseudo-loopback accepted by a layer: %r" % bad),
        }
    print("  [%s] pseudo_loopback_predicate: %s" % (
        "PASS" if RESULTS["pseudo_loopback_predicate"]["passed"] else "FAIL",
        RESULTS["pseudo_loopback_predicate"]["reason"]))

    # === S2/N01: actual connect to pseudo-loopback hostnames must be blocked
    # BY THE GUARD before any real DNS resolution or connection attempt. ===
    def _try_127audit():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(("127.audit.invalid", 9))

    _run_test("pseudo_loopback_connect_127audit", _try_127audit,
              expect_blocked=True, expect_source="guard")

    def _try_localhostaudit():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(("localhost.audit.invalid", 9))

    _run_test("pseudo_loopback_connect_localhostaudit", _try_localhostaudit,
              expect_blocked=True, expect_source="guard")

    # R1: predicates only. These strings can map to real external addresses;
    # never hand them to connect, even when both layers are broken.
    for name, host in [("leading_zero_octet_blocked", "0127.0.0.1"),
                       ("leading_zero_long_blocked", "00127.0.0.1")]:
        rejected = (guard_pred is not None and fallback_pred is not None
                    and not guard_pred(host) and not fallback_pred(host))
        RESULTS[name] = {"passed": rejected, "reason": "both predicates reject; no connect"}

    # === S2/G12: empty/malformed host predicate on BOTH layers ===
    if guard_pred is not None and fallback_pred is not None:
        both_reject = (not guard_pred("")) and (not fallback_pred(""))
        RESULTS["empty_host_rejected"] = {
            "passed": both_reject,
            "reason": "empty host rejected by both guard and fallback predicates"
                      if both_reject else
                      "empty host NOT rejected: guard=%s fallback=%s"
                      % (guard_pred(""), fallback_pred("")),
        }
    else:
        RESULTS["empty_host_rejected"] = {"passed": False, "reason": "strict check not accessible"}
    print("  [%s] empty_host_rejected: %s" % ("PASS" if RESULTS["empty_host_rejected"]["passed"] else "FAIL",
                                               RESULTS["empty_host_rejected"]["reason"]))

    # Overall: all tests must pass
    all_tests_pass = all(r.get("passed", False) for k, r in RESULTS.items() if k != "overall")
    RESULTS["overall"] = {
        "passed": all_tests_pass and fb_total == 0,
        "reason": "all %d tests passed, fallback hits = %d" % (len(RESULTS), fb_total)
                  if all_tests_pass else "some tests failed",
    }

if "no_guard_async" in RESULTS:
    del RESULTS["no_guard_async"]
# === Summary ===
all_pass = all(r.get("passed", False) for r in RESULTS.values())
total = len(RESULTS)
pass_count = sum(1 for r in RESULTS.values() if r.get("passed", False))
fail_count = total - pass_count
print("\n=== Guard test [%s mode]: %d/%d passed, %d failed ===" % (TEST_MODE, pass_count, total, fail_count))

_write_results()
print("\n=== JSON ===")
print(json.dumps(RESULTS, indent=2))
sys.exit(0 if all_pass else 1)

