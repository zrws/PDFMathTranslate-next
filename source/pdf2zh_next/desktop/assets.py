"""Offline verification and explicit, short-lived asset download worker."""
import hashlib
import json
import os
import subprocess
import sys
import threading
from pathlib import Path


class Assets:
    def __init__(self, home, store):
        self.cache = Path(home)/".cache/babeldoc"
        self.manifest_path = Path(__file__).with_name("assets.lock.json")
        self.manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        self.store = store
        self.lock = threading.RLock()
        self.busy = False
        self.cancelled=threading.Event()
        self.child=None
        self.state = {"state": "verifying", "message": "正在核对离线资源（不会阻塞设置和历史）", "completed_bytes": 0, "total_bytes": sum(row["bytes"] for row in self.manifest), "phase": "verifying"}

    def status(self):
        with self.lock: return dict(self.state)

    def _set(self, **changes):
        with self.lock:
            self.state.update(changes)
            data = dict(self.state)
        self.store.emit("assets.updated", data)

    def verify(self):
        complete = 0
        missing = []
        for row in self.manifest:
            file = self.cache/row["path"]
            try:
                digest = hashlib.sha3_256()
                with file.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(1024*1024), b""): digest.update(chunk)
                if file.stat().st_size != row["bytes"] or digest.hexdigest() != row["sha3_256"]: raise ValueError("hash")
                complete += row["bytes"]
            except (OSError, ValueError): missing.append(row["path"])
        self._set(state="missing" if missing else "ready", phase="missing" if missing else "ready", completed_bytes=complete, message=f"缺少或损坏 {len(missing)} 项资源，请点击「准备 / 重试资源」。" if missing else "排版资源已校验 · 可以开始翻译", missing_count=len(missing))
        return not missing

    def prepare(self):
        with self.lock:
            if self.busy: return self.status()
            self.busy = True
            self.cancelled.clear()
        threading.Thread(target=self._download, daemon=True).start()
        return self.status()

    def _download(self):
        child = None
        try:
            with self.lock:
                if self.cancelled.is_set():return
                self._set(state="downloading", phase="downloading", message="正在下载排版资源，翻译进度单独显示…")
            child = subprocess.Popen([sys.executable, "-m", "pdf2zh_next.desktop.worker"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=0x08000000 if os.name == "nt" else 0)
            with self.lock:self.child=child
            while child.poll() is None:
                if self.cancelled.is_set():child.kill();child.wait(3);return
                complete = sum(min((self.cache/row["path"]).stat().st_size, row["bytes"]) for row in self.manifest if (self.cache/row["path"]).is_file())
                self._set(completed_bytes=complete)
                try: child.wait(timeout=1)
                except subprocess.TimeoutExpired: pass
            if child.returncode: raise RuntimeError("download")
            self._set(state="verifying", phase="verifying", message="下载完成，正在校验资源…")
            self.verify()
        except Exception:
            if self.cancelled.is_set():self._set(state="missing",phase="cancelled",message="资源准备已取消，可稍后重试。")
            else:self._set(state="failed_retryable", phase="failed_retryable", message="资源准备失败，请检查网络与磁盘空间后重试。")
        finally:
            with self.lock:
                if self.cancelled.is_set():self._set(state="missing",phase="cancelled",message="资源准备已取消，可稍后重试。")
                self.busy = False;self.child=None

    def close(self):
        self.cancelled.set()
        with self.lock:child=self.child
        if child is not None and child.poll() is None:child.kill();child.wait(3)
        if self.busy:self._set(state="missing",phase="cancelled",message="资源准备已取消，可稍后重试。")
