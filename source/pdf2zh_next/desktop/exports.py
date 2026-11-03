"""Versioned streaming export and content-bound, durable receipts."""
import copy
import datetime
import os
import re
import shutil
import threading
import uuid
from pathlib import Path

from .storage import file_identity, fingerprint


def directory(value):
    path = Path(value)
    if not path.is_absolute() or str(path).startswith(("\\\\.\\", "\\\\?\\")):
        raise ValueError("请选择有效的绝对保存目录。")
    return path.resolve()


def safe_stem(filename):
    stem = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", Path(filename).stem).strip(" .")[:100] or "文档"
    if stem.upper() in {"CON", "PRN", "AUX", "NUL", *("COM"+str(i) for i in range(1, 10)), *("LPT"+str(i) for i in range(1, 10))}: stem = "_"+stem
    return stem


class Exports:
    def __init__(self, store):
        self.store = store
        self.lock = threading.RLock()

    @staticmethod
    def retained_task(task):
        value=copy.deepcopy(task)
        value.pop("file_path",None);value.pop("cancel_requested",None)
        value["options"]={"export_dir":task.get("options",{}).get("export_dir","")}
        return value

    def durable(self, mutate):
        with self.store.lock:
            before=copy.deepcopy(self.store.state)
            try:mutate(self.store.state);self.store._persist()
            except Exception:self.store.state=before;raise

    def receipt(self, payload):
        with self.lock:
            task = self.store.retained(payload["task_id"])
            if not task or task["status"] != "done": raise ValueError("任务尚无可保存的产物。")
            output = task["outputs"].get(payload["kind"])
            if not output or payload["output_revision"] != output["output_revision"] or any(payload[k] != output[k] for k in ("size_bytes", "sha256")):
                raise ValueError("保存回执与产物内容或修订不一致，暂存产物已保留。")
            immutable = {k: payload[k] for k in ("task_id", "kind", "output_revision", "saved_path", "size_bytes", "sha256")}
            old = self.store.state["receipts"].get(payload["export_id"])
            if old:
                if old["identity"] != immutable: raise ValueError("同一保存标识不能换目标路径、修订或内容。")
            saved = directory(payload["saved_path"])
            status = "pending_verification"
            try:
                actual = file_identity(saved)
                if actual == {k: output[k] for k in ("size_bytes", "sha256")}: status = "verified"
            except OSError:
                pass
            record = {"export_id": payload["export_id"], "identity": immutable, "status": status, "saved_at": old.get("saved_at") if old else payload.get("saved_at"),"task":self.retained_task(task)}
            self.durable(lambda state:state["receipts"].__setitem__(payload["export_id"],record))
            if status=="verified" and str(saved) not in task.get("saved_paths",[]):
                current=self.store.retained(task["id"])
                self.store.saved(task["id"],current.get("saved_paths",[])+[str(saved)])
            # Policy: retain staging. No path-existence-based destructive cleanup.
            return copy.deepcopy({k:v for k,v in record.items() if k!="task"})

    def save(self, task_id, destination, export_id):
        uuid.UUID(export_id)
        target = directory(destination)
        with self.lock:
            task = self.store.retained(task_id)
            if not task or task["status"] != "done" or not task["outputs"]: raise ValueError("请选择已完成且有输出的任务。")
            request_hash = fingerprint({"task_id": task_id, "directory": str(target), "outputs": {kind:{k:out[k] for k in ("output_revision","size_bytes","sha256")} for kind,out in task["outputs"].items()}})
            existing = self.store.state["exports"].get(export_id)
            if existing and existing["fingerprint"] != request_hash: raise ValueError("同一保存请求不能修改内容或目录。")
            if not existing:
                self.durable(lambda state:state["exports"].__setitem__(export_id,{"fingerprint":request_hash,"files":{},"task":self.retained_task(task)}))
            with self.store.lock:operation = copy.deepcopy(self.store.state["exports"][export_id])
            stem = safe_stem(task["filename"])
            folder = target/(stem+"_"+datetime.date.today().isoformat())
            folder.mkdir(parents=True, exist_ok=True)
            required = sum(o["size_bytes"] for o in task["outputs"].values())
            if shutil.disk_usage(folder).free < required+8*1024*1024: raise ValueError("保存目录磁盘空间不足，请更换目录。暂存产物已保留。")
            for kind, output in task["outputs"].items():
                if kind not in {"dual", "mono", "glossary"}: continue
                saved = operation["files"].get(kind)
                if saved:
                    path = Path(saved)
                    if path.exists():
                        if file_identity(path) != {k: output[k] for k in ("size_bytes", "sha256")}: raise ValueError("上次保存的文件已改变，请发起一次新的保存。暂存仍保留。")
                    else:
                        self._copy(Path(output["path"]), path, output)
                else:
                    suffix = ".csv" if kind == "glossary" else ".pdf"
                    label = {"dual": "双语", "mono": "单语", "glossary": "术语"}[kind]
                    version = 1
                    while True:
                        path = folder/(stem+"_"+label+("" if version == 1 else f"_v{version}")+suffix)
                        reservation = path.with_name(path.name+".reserve")
                        try:
                            with reservation.open("x", encoding="ascii") as stream: stream.write(export_id)
                        except FileExistsError:
                            version += 1
                            continue
                        if path.exists():
                            reservation.unlink()
                            version += 1
                            continue
                        break
                    try:
                        operation["files"][kind] = str(path)
                        self.durable(lambda state:state["exports"].__setitem__(export_id,copy.deepcopy(operation))) # intent before copy
                        self._copy(Path(output["path"]), path, output)
                    finally:
                        reservation.unlink(missing_ok=True)
                receipt_id = str(uuid.uuid5(uuid.UUID(export_id), kind))
                self.receipt({"export_id": receipt_id, "task_id": task_id, "kind": kind, "output_revision": output["output_revision"], "saved_path": str(path), "size_bytes": output["size_bytes"], "sha256": output["sha256"]})
            paths = list(dict.fromkeys(self.store.retained(task_id).get("saved_paths", [])+list(operation["files"].values())))
            return self.store.saved(task_id,paths)

    @staticmethod
    def _copy(source, target, identity):
        if target.exists(): raise ValueError("目标文件已存在，请重新选择版本。")
        partial = target.with_name(target.name+"."+uuid.uuid4().hex+".partial")
        try:
            with source.open("rb") as src, partial.open("xb") as dest:
                shutil.copyfileobj(src, dest, length=1024*1024)
                dest.flush()
                os.fsync(dest.fileno())
            if file_identity(partial) != {k: identity[k] for k in ("size_bytes", "sha256")}: raise ValueError("文件校验失败，未提交保存。")
            # Same-volume hard link is atomic and refuses replacement on Windows/Linux.
            if os.name == "nt": os.rename(partial, target)  # Windows refuses replacement, including FAT/SMB.
            else: os.link(partial, target)
        finally:
            partial.unlink(missing_ok=True)
