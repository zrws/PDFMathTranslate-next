"""Single-writer durable task state, replay journal, and idempotency tombstones."""
import copy
import hashlib
import json
import os
import threading
import time
import uuid
from collections import deque
from pathlib import Path

TERMINAL = {"done", "failed", "cancelled"}


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name+"."+uuid.uuid4().hex+".partial")
    try:
        with temp.open("x", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, separators=(",", ":"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def file_identity(path):
    digest = hashlib.sha256()
    size = 0
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            size += len(chunk)
            digest.update(chunk)
    return {"size_bytes": size, "sha256": digest.hexdigest()}


class Store:
    def __init__(self, home, downloads):
        self.path = Path(home)/"config/desktop-state.json"
        self.lock = threading.RLock()
        self.condition = threading.Condition(self.lock)
        self.instance_id = uuid.uuid4().hex
        self.seq = 0
        self.events = deque(maxlen=1024)
        self.last_progress = {}
        self.state = {"tasks": {}, "keys": {}, "receipts": {}, "exports": {}, "prefs": {"download_dir": str(downloads), "resource_tier": "balanced", "requested_qps": 4}}
        if self.path.exists():
            # Corruption is a visible startup error; never overwrite user history.
            self.state = json.loads(self.path.read_text(encoding="utf-8-sig"))
        for task in self.state["tasks"].values():
            if task["status"] not in TERMINAL:
                task.update(status="failed", stage="任务已中断", error="应用上次退出时任务未完成，请重试。", finished_at=time.time(), revision=task.get("revision", 0)+1)
        self._persist()

    def _persist(self):
        atomic_json(self.path, self.state)

    @staticmethod
    def public(task):
        result = copy.deepcopy(task)
        for key in ("file_path", "cancel_requested", "hidden"):
            result.pop(key, None)
        for key in ("settings_snapshot", "credential_fields"):
            result.get("options", {}).pop(key, None)
        if result.get("status")=="done" and result.get("saved_paths"):
            result["stage"]="已有结果保存记录";result["message"]="文件已保存，可打开结果或目录"
        result["output_identities"] = result.get("outputs", {})
        result["outputs"] = {kind: data["path"] for kind, data in result.get("outputs", {}).items()}
        return result

    def _emit(self, event_type, data, task_id=None):
        self.seq += 1
        if event_type == "snapshot": data = {**data, "last_event_id": self.seq}
        event = {"instance_id": self.instance_id, "event_id": self.seq, "ts": time.time(), "type": event_type, "task_id": task_id, "data": copy.deepcopy(data)}
        self.events.append(event)
        self.condition.notify_all()
        return event

    def emit(self, event_type, data):
        with self.lock:
            return self._emit(event_type, data)

    def history(self, cursor=None, limit=50):
        with self.lock:
            rows = sorted((t for t in self.state["tasks"].values() if not t.get("hidden")), key=lambda t: (t["created_at"], t["id"]), reverse=True)
            active = [self.public(t) for t in rows if t["status"] not in TERMINAL]
            history = [t for t in rows if t["status"] in TERMINAL]
            if cursor:
                timestamp, ident = cursor.split(":", 1)
                history = [t for t in history if (t["created_at"], t["id"]) < (float(timestamp), ident)]
            page = history[:max(1, min(100, limit))]
            next_cursor = f'{page[-1]["created_at"]}:{page[-1]["id"]}' if len(history)>len(page) and page else None
            return {"active": active, "history": [self.public(t) for t in page], "next_cursor": next_cursor}

    def get(self, ident):
        with self.lock:
            task = self.state["tasks"].get(ident)
            return copy.deepcopy(task) if task else None

    def retained(self, ident):
        with self.lock:
            task=self.state["tasks"].get(ident)
            if task:return copy.deepcopy(task)
            for record in self.state["keys"].values():
                if record["task_id"]==ident and time.time()-record["ts"]<86400:
                    return copy.deepcopy(record["response"])
            for group in ("exports","receipts"):
                for record in self.state[group].values():
                    if record.get("task",{}).get("id")==ident:return copy.deepcopy(record["task"])
            return None

    def saved(self, ident, paths):
        with self.lock:
            if ident in self.state["tasks"]:return self.update(ident,persist=True,saved_paths=paths)
            previous=copy.deepcopy(self.state);result=None
            for record in self.state["keys"].values():
                if record["task_id"]==ident and time.time()-record["ts"]<86400:
                    record["response"]["saved_paths"]=paths
                    record["response"]["revision"]+=1
                    result=copy.deepcopy(record["response"])
            for group in ("exports","receipts"):
                for record in self.state[group].values():
                    if record.get("task",{}).get("id")==ident:
                        record["task"]["saved_paths"]=paths
                        record["task"]["revision"]+=1
                        result=copy.deepcopy(record["task"])
            if result is None:raise ValueError("任务的恢复期限已过，请重新创建任务。")
            try:self._persist()
            except Exception:self.state=previous;raise
            return result

    def lookup(self, key, parent=None):
        with self.lock:
            namespace=("retry:"+parent+":" if parent else "create:")+key
            record=self.state["keys"].get(namespace)
            return copy.deepcopy(record) if record and time.time()-record["ts"]<86400 else None

    def create(self, key, payload_hash, file, options, parent=None, request_hash=None):
        with self.lock:
            now = time.time()
            namespace = ("retry:"+parent+":" if parent else "create:")+key
            old = self.state["keys"].get(namespace)
            if old and now-old["ts"]<86400:
                if old["fingerprint"] != payload_hash:
                    raise ValueError("同一请求标识的内容已改变，请确认任务后重新提交。")
                return copy.deepcopy(old["response"] if old["task_id"] not in self.state["tasks"] else self.state["tasks"][old["task_id"]]), False
            ident = uuid.uuid4().hex[:16]
            task = {"id": ident, "filename": file["filename"], "file_path": file["path"], "file_sha256": file["sha256"], "page_count": file["page_count"], "lang_in": options["lang_in"], "lang_out": options["lang_out"], "options": copy.deepcopy(options), "status": "queued", "phase": "preparing", "stage": "等待资源与工作线程", "message": "排队中", "error": "", "progress": 0, "revision": 1, "created_at": now, "finished_at": None, "outputs": {}, "saved_paths": [], "parent_task_id": parent, "cancel_requested": False}
            previous = copy.deepcopy(self.state)
            self.state["tasks"][ident] = task
            self.state["keys"] = {k: v for k,v in self.state["keys"].items() if now-v["ts"]<86400}
            self.state["keys"][namespace] = {"fingerprint": payload_hash, "request_hash": request_hash, "task_id": ident, "response": copy.deepcopy(task), "ts": now}
            try: self._persist()
            except Exception:
                self.state = previous
                raise
            self._emit("task.created", self.public(task), ident)
            return copy.deepcopy(task), True

    def update(self, ident, persist=False, **changes):
        with self.lock:
            task = self.state["tasks"][ident]
            if task["status"] in TERMINAL and changes.get("status", task["status"]) not in TERMINAL:
                return copy.deepcopy(task)
            if task["status"] in TERMINAL and not set(changes)<= {"saved_paths"}:
                return copy.deepcopy(task)
            previous = copy.deepcopy(task)
            task.update(changes)
            task["revision"] += 1
            final = task["status"] in TERMINAL
            if persist or final:
                try: self._persist()
                except Exception:
                    self.state["tasks"][ident] = previous
                    raise
            now = time.monotonic()
            if final or persist or now-self.last_progress.get(ident, 0)>=0.25:
                self.last_progress[ident] = now
                self._emit("task.final" if final else "task.updated", self.public(task), ident)
            return copy.deepcopy(task)

    def start(self, ident):
        with self.lock:
            task = self.state["tasks"][ident]
            if task["status"] != "queued" or task["cancel_requested"]: return False
            self.update(ident, persist=True, status="running", phase="preparing", stage="准备翻译引擎", message="按任务配置加载翻译引擎")
            return True

    def cancel(self, ident):
        with self.lock:
            task = self.state["tasks"][ident]
            if task["status"] == "queued":
                return self.update(ident, persist=True, status="cancelled", stage="已取消", message="未启动翻译", finished_at=time.time(), cancel_requested=True)
            if task["status"] == "running":
                return self.update(ident, persist=True, cancel_requested=True, message="正在取消并回收工作进程…")
            return copy.deepcopy(task)

    def clear(self):
        with self.lock:
            previous = copy.deepcopy(self.state)
            for ident,task in list(self.state["tasks"].items()):
                if task["status"] in TERMINAL:
                    for record in self.state["keys"].values():
                        if record["task_id"]==ident: record["response"]=copy.deepcopy(task)
                    for group in ("exports","receipts"):
                        for record in self.state[group].values():
                            if record.get("task",{}).get("id")==ident:
                                record["task"]["saved_paths"]=copy.deepcopy(task["saved_paths"])
                                record["task"]["revision"]=task["revision"]
                    del self.state["tasks"][ident]
            try: self._persist()
            except Exception:
                self.state = previous
                raise
            self._emit("snapshot", self.snapshot())

    def fail(self, ident, message):
        with self.lock:
            task=self.state["tasks"].get(ident)
            if not task or task["status"] in TERMINAL:return
            task.update(status="failed",stage="任务未完成",error=message,message=message,finished_at=time.time(),revision=task["revision"]+1)
            try:self._persist()
            except OSError:task["state_storage"]="unsaved"
            self._emit("task.final",self.public(task),ident)

    def snapshot(self):
        with self.lock:
            page = self.history()
            return {"tasks": page["active"]+page["history"], "next_cursor": page["next_cursor"], "last_event_id": self.seq}

    def read_events(self, cursor):
        with self.lock:
            if not cursor or cursor[0] != self.instance_id:
                return [{"instance_id": self.instance_id, "event_id": self.seq, "type": "snapshot", "task_id": None, "ts": time.time(), "data": self.snapshot()}]
            seq = cursor[1]
            if seq>self.seq or self.events and seq<self.events[0]["event_id"]-1:
                return [{"instance_id": self.instance_id, "event_id": self.seq, "type": "resync", "task_id": None, "ts": time.time(), "data": {"reason": "gap"}}]
            return [copy.deepcopy(e) for e in self.events if e["event_id"]>seq]

    def wait(self, seq):
        with self.condition:
            if seq == self.seq: self.condition.wait(10)

    def prefs(self, changes=None):
        with self.lock:
            if changes:
                previous = copy.deepcopy(self.state["prefs"])
                self.state["prefs"].update(changes)
                try: self._persist()
                except Exception:
                    self.state["prefs"] = previous
                    raise
                self._emit("settings.updated", {"changed": True})
            return copy.deepcopy(self.state["prefs"])
