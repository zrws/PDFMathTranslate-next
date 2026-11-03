"""Backend data ownership and conservative legacy migration."""
import json
import os
import shutil
import uuid
from pathlib import Path
from .storage import atomic_json, file_identity


class DataOwner:
    def __init__(self, home):
        self.home = Path(home).resolve()
        self.home.mkdir(parents=True, exist_ok=True)
        self.file = (self.home/".writer.lock").open("a+b")
        self.file.seek(0); self.file.write(b"0"); self.file.flush(); self.file.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

    def close(self): self.file.close()


def migrate_config(home, legacy_root):
    """Never replace a current config. Copy/verify first, then atomic switch."""
    home = Path(home)
    marker = home/"config/migration-v1.json"
    if marker.exists(): return
    source = Path(legacy_root)/"home/.config/pdf2zh/config.v3.toml"
    target = home/".config/pdf2zh/config.v3.toml"
    migrated = []
    if source.is_file() and source.resolve() != target.resolve() and not target.exists():
        backup = home/"config/legacy-backup"/uuid.uuid4().hex
        backup.mkdir(parents=True)
        shutil.copy2(source, backup/"config.v3.toml")
        if file_identity(source) != file_identity(backup/"config.v3.toml"): raise ValueError("旧配置备份校验失败")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name+".migration.partial")
        shutil.copy2(backup/"config.v3.toml", temporary)
        os.replace(temporary, target)
        migrated.append({"source": str(source), "backup": str(backup), "target": str(target)})
    atomic_json(marker, {"version": 1, "config": migrated, "policy": "originals retained; current config never overwritten; history migration separately reconciled"})


def migrate_history(home, legacy_root, store):
    marker = Path(home)/"config/history-migration-v1.json"
    if marker.exists(): return
    legacy = Path(legacy_root)/"pdf2zh_files"
    source = legacy/"tasks.json"
    imported = 0
    missing = 0
    if source.is_file() and not store.state["tasks"]:
        raw = json.loads(source.read_text(encoding="utf-8-sig"))
        backup = Path(home)/"config/legacy-history-backup.json"
        if not backup.exists(): shutil.copy2(source, backup)
        if file_identity(backup) != file_identity(source): raise ValueError("旧历史备份校验失败，未切换")
        for old in raw.get("tasks", []):
            ident = str(old["id"])
            if not ident.isalnum(): continue
            task = {k: old[k] for k in ("filename", "lang_in", "lang_out", "created_at", "progress", "message", "error", "finished_at", "page_count") if k in old}
            task.update(id=ident, status=old.get("status", "failed"), revision=1, phase="finalizing", stage="已迁移的历史", options={}, outputs={}, saved_paths=[], file_path="", file_sha256="", cancel_requested=False)
            if task["status"] not in {"done", "failed", "cancelled"}: task.update(status="failed", error="旧入口的任务未完成，请重新导入 PDF。")
            for kind, path in old.get("outputs", {}).items():
                original = Path(path).resolve()
                if kind not in {"dual", "mono", "glossary"} or not original.is_relative_to((legacy/"outputs").resolve()) or not original.is_file():
                    missing += 1
                    continue
                dest = Path(home)/"work/outputs"/ident/original.name
                dest.parent.mkdir(parents=True, exist_ok=True)
                if not dest.exists(): shutil.copy2(original, dest)
                identity = file_identity(original)
                if file_identity(dest) != identity: raise ValueError("旧产物复制校验失败，原件已保留")
                task["outputs"][kind] = {"path": str(dest), "output_revision": 1, **identity}
            task.setdefault("created_at", 0); task.setdefault("filename", "历史文档.pdf")
            store.state["tasks"][ident] = task
            imported += 1
        store._persist()
    atomic_json(marker, {"version": 1, "imported": imported, "missing_outputs": missing, "originals_retained": True})
