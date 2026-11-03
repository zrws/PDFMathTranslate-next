"""Test-only entry gate: verifies guard activation BEFORE any app code runs.

This module is imported by entry_wrapper.py (and only by test harnesses) so
that it runs before the target application script. Gate checks, in order:

1. PDF2ZH_GUARD_LOG is set and the log file exists and is readable.
2. Hash binding (S1): when PDF2ZH_GUARD_SHA256 is set, the sitecustomize
   module ACTUALLY LOADED in this process (sys.modules) must exist and its
   file must match the expected SHA256. If sitecustomize is not in
   sys.modules, the guard never loaded (Python silently ignores
   sitecustomize import errors) and the gate refuses regardless of any log
   content. This blocks startup even when Python swallowed an import error.
3. The log contains a GUARD_ACTIVE entry for THIS process (PID match) -
   a stale handshake from an old run/PID cannot back this startup.
4. The guard log is writable (ENTRY_GATE_OK appended).
5. On success writes "APP_ENTERED <pid> <run_id>".

All failure paths sys.exit(1) BEFORE any application code runs.
"""

import hashlib
import os
import sys

_LOG = os.environ.get("PDF2ZH_GUARD_LOG", "")
_RUN_ID = os.environ.get("PDF2ZH_RUN_ID", "no-run-id")
_EXPECTED_SHA = os.environ.get("PDF2ZH_GUARD_SHA256", "")
_PID = os.getpid()


def _die(msg):
    sys.stderr.write("ENTRY_GATE: %s\n" % msg)
    sys.exit(1)


if not _LOG:
    # Guard is not configured; this child cannot be safely measured
    _die("PDF2ZH_GUARD_LOG not set; refusing to start")

if not os.path.isfile(_LOG):
    _die("guard log does not exist: %s" % _LOG)

try:
    with open(_LOG, "r", encoding="utf-8") as f:
        content = f.read()
except Exception as e:
    _die("cannot read guard log: %s" % e)

# S1 hash binding: the guard module actually loaded in THIS process must
# match the expected hash. Python silently ignores sitecustomize import
# errors, so sys.modules is the only trustworthy witness of a real load.
if _EXPECTED_SHA:
    mod = sys.modules.get("sitecustomize")
    if mod is None or not getattr(mod, "__file__", None):
        _die(
            "sitecustomize module not loaded in this process (Python ignores "
            "sitecustomize import errors); guard cannot be verified; "
            "refusing to start"
        )
    try:
        with open(mod.__file__, "rb") as f:
            actual = hashlib.sha256(f.read()).hexdigest().upper()
    except Exception as e:
        _die("cannot hash loaded sitecustomize %r: %s" % (mod.__file__, e))
    if actual != _EXPECTED_SHA.upper():
        _die(
            "guard hash mismatch: expected %s, loaded sitecustomize is %s; "
            "refusing to start" % (_EXPECTED_SHA.upper(), actual)
        )

# Check for a GUARD_ACTIVE entry with THIS PID
guard_ok = False
for line in content.splitlines():
    if line.startswith("GUARD_ACTIVE"):
        parts = line.split()
        if len(parts) >= 2:
            try:
                guard_pid = int(parts[1])
                if guard_pid == _PID:
                    guard_ok = True
                    break
            except ValueError:
                pass

if not guard_ok:
    _die(
        "no GUARD_ACTIVE entry with PID %d in guard log; "
        "guard hooks not installed in this process (stale or missing "
        "handshake). Refusing to start." % _PID
    )

# Verify the guard log is writable (guard was active, now confirm append)
try:
    with open(_LOG, "a", encoding="utf-8") as f:
        f.write("ENTRY_GATE_OK %d %s\n" % (_PID, _RUN_ID))
except Exception as e:
    _die("guard log not writable: %s" % e)

# If we reach here, the guard is confirmed active with this PID, the loaded
# guard matches the expected hash, and the log is writable.
# Write APP_ENTERED sentinel so the measurement harness can verify.
try:
    with open(_LOG, "a", encoding="utf-8") as f:
        f.write("APP_ENTERED %d %s\n" % (_PID, _RUN_ID))
except Exception:
    pass
