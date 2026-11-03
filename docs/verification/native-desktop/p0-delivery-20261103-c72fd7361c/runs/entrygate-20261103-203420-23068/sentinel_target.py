import os, sys
p = os.environ.get("SENTINEL_PATH", "")
if p:
    with open(p, "w", encoding="utf-8") as f:
        f.write("TARGET_RAN pid=%d\n" % os.getpid())
sys.exit(0)
