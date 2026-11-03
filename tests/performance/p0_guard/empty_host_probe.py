"""Frozen-case G12 standalone probe: empty hostname NOT treated as loopback.

Frozen semantics (CASE_MANIFEST G12, expected_exit=1, reason
empty_host_rejected): the observable is a DEDICATED probe whose exit code
is 1 WHEN the rejection is correctly observed (same direction as G04/G05/
G15: correct rejection = exit 1). If any layer wrongly treats '' as
loopback, the probe exits 0 (and the case fails with verdict mismatch).

Test-only. No product code. No network attempt is made - pure predicate.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guard_fallback  # noqa: E402
import sitecustomize    # noqa: E402

guard_pred = getattr(sitecustomize, "_is_loopback", None)
fb_pred = getattr(guard_fallback, "_is_loopback_strict", None)

guard_rejects = (guard_pred is not None) and (guard_pred("") is False)
fb_rejects = (fb_pred is not None) and (fb_pred("") is False)

if guard_rejects and fb_rejects:
    print("EMPTY_HOST_REJECTED guard=False fallback=False")
    sys.exit(1)

print(
    "EMPTY_HOST_WRONGLY_ACCEPTED guard=%s fallback=%s"
    % (
        guard_pred("") if guard_pred else "no-predicate",
        fb_pred("") if fb_pred else "no-predicate",
    )
)
sys.exit(0)
