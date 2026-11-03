"""Apply locked BabelDOC patches to an owned staging environment, fail closed."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def apply(site_packages):
    root = Path(__file__).resolve().parent.parent
    target = Path(site_packages).resolve()
    if not target.is_relative_to(root) or target == root: raise ValueError("补丁目标必须位于本项目的构建暂存目录")
    metadata = target/"babeldoc-0.6.2.dist-info/METADATA"
    if not metadata.is_file() or "Version: 0.6.2" not in metadata.read_text(encoding="utf-8"): raise ValueError("需要锁定 BabelDOC 0.6.2")
    patches = Path(__file__).with_name("patches")/"babeldoc"
    lock = json.loads((patches/"patch-lock.json").read_text(encoding="utf-8"))
    for patch in lock["patches"]:
        for row in patch["files"]:
            path=target/row["path"];raw=path.read_bytes();canonical=raw.replace(b"\r\n",b"\n")
            if raw!=canonical and hashlib.sha256(canonical).hexdigest().upper() in {row["original_sha256"],row["patched_sha256"]}:
                path.write_bytes(canonical)
        actual = [sha(target/row["path"]) for row in patch["files"]]
        if actual == [row["patched_sha256"] for row in patch["files"]]: continue
        if actual != [row["original_sha256"] for row in patch["files"]]: raise ValueError("引擎文件哈希不符，拒绝覆盖："+patch["file"])
        # Normalize mail-patch CRLF without changing the locked source bytes.
        body = (patches/patch["file"]).read_text(encoding="utf-8")
        body = body[body.index("diff --git "):]
        with tempfile.TemporaryDirectory(prefix="pdf2zh-engine-patch-") as scratch:
            temp = Path(scratch)/"patch.diff"
            temp.write_text(body, encoding="utf-8", newline="\n")
            args = ["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf", "apply", "--directory="+target.relative_to(root).as_posix()]
            subprocess.run(args+["--check", str(temp)], cwd=root, check=True, capture_output=True)
            subprocess.run(args+[str(temp)], cwd=root, check=True, capture_output=True)
        if [sha(target/row["path"]) for row in patch["files"]] != [row["patched_sha256"] for row in patch["files"]]: raise ValueError("引擎补丁结果哈希不符")
    return lock


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--site-packages", required=True)
    print(json.dumps(apply(parser.parse_args().site_packages), ensure_ascii=False))
