import sys, os
guard_dir = os.environ.get("CASE4_GUARD_DIR", "")
sys.path.insert(0, guard_dir)
import guard_fallback
import sitecustomize
import socket
s = socket.socket()
try:
    s.connect(("192.0.2.1", 9))
    print("CONNECTED-BAD")
except OSError as e:
    if "net-guard" in str(e):
        print("BLOCKED-BY-GUARD")
    elif "FALLBACK" in str(e):
        print("BLOCKED-BY-FALLBACK")
    else:
        print("BLOCKED-BY-OS: %s" % str(e)[:80])
