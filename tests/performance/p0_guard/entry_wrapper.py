"""Entry wrapper: runs the guard entry gate, then the target application script.

Measurement scripts set:
- PDF2ZH_GUARD_LOG: guard log path (guard already loaded via sitecustomize)
- PDF2ZH_GUARD_DIR: directory containing entry_gate.py and sitecustomize.py
- PDF2ZH_TARGET_SCRIPT: absolute path to the target script (e.g. start-webui.py)
- PDF2ZH_TARGET_ARGS: space-separated args for the target script

This wrapper ensures the entry gate runs BEFORE the target script, providing
the pre-app startup gate required by S1. If the gate fails, sys.exit(1) is
called and the target script is never executed.
"""

import os
import sys
import json

guard_dir = os.environ.get("PDF2ZH_GUARD_DIR", "")
target_script = os.environ.get("PDF2ZH_TARGET_SCRIPT", "")
target_args = os.environ.get("PDF2ZH_TARGET_ARGS", "")

if not guard_dir:
    sys.stderr.write("ENTRY_WRAPPER: PDF2ZH_GUARD_DIR not set\n")
    sys.exit(1)
if not target_script:
    sys.stderr.write("ENTRY_WRAPPER: PDF2ZH_TARGET_SCRIPT not set\n")
    sys.exit(1)
if not os.path.isfile(target_script):
    sys.stderr.write("ENTRY_WRAPPER: target script not found: %s\n" % target_script)
    sys.exit(1)

# Import the entry gate (checks guard activation, writes APP_ENTERED, exits on failure)
sys.path.insert(0, guard_dir)
import entry_gate  # noqa: F401,E402 - this will sys.exit(1) if guard is not OK

# Run the target script
if "PDF2ZH_TARGET_ARGS_JSON" in os.environ:
    args = json.loads(os.environ["PDF2ZH_TARGET_ARGS_JSON"])
    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        raise ValueError("target args must be a JSON string array")
    sys.argv = [target_script] + args
else:
    sys.argv = [target_script] + target_args.split() if target_args else [target_script]
_target_dir = os.path.dirname(os.path.abspath(target_script))
if _target_dir not in sys.path:
    sys.path.insert(0, _target_dir)

with open(target_script, "r", encoding="utf-8-sig") as _f:
    _code = compile(_f.read(), target_script, "exec")

exec(_code)
