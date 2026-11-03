"""Crash-recoverable transaction across the legacy TOML and desktop prefs."""
import base64
import json
import os
import uuid
from pathlib import Path
from .storage import atomic_json


def atomic_bytes(path, data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+"."+uuid.uuid4().hex+".partial")
    try:
        with temp.open("xb") as out: out.write(data);out.flush();os.fsync(out.fileno())
        os.replace(temp,path)
    finally: temp.unlink(missing_ok=True)


def recover(home):
    home=Path(home);journal=home/"config/settings-transaction.private.json"
    if not journal.exists(): return
    record=json.loads(journal.read_text(encoding="utf-8"))
    if record["phase"]=="prepared":
        target=home/".config/pdf2zh/config.v3.toml"
        if record["config_before"] is None: target.unlink(missing_ok=True)
        else: atomic_bytes(target,base64.b64decode(record["config_before"]))
        state_path=home/"config/desktop-state.json"
        if state_path.exists():
            state=json.loads(state_path.read_text(encoding="utf-8"));state["prefs"]=record["prefs_before"];atomic_json(state_path,state)
    elif record["phase"]!="committed": raise ValueError("设置事务记录无效，请保留数据目录并重试。")
    journal.unlink()


def commit(home,store,apply,restore_memory,changes):
    home=Path(home);target=home/".config/pdf2zh/config.v3.toml";journal=home/"config/settings-transaction.private.json"
    if journal.exists():
        old=json.loads(journal.read_text(encoding="utf-8"))
        if old.get("phase")!="committed":raise ValueError("上次设置恢复尚未完成，请重启服务后重试；原事务记录已保留。")
        journal.unlink()
    record={"phase":"prepared","config_before":base64.b64encode(target.read_bytes()).decode() if target.exists() else None,"prefs_before":store.prefs()}
    atomic_json(journal,record)  # private config journal; never an event/history/log
    try:
        apply()
        store.prefs(changes)
        atomic_json(journal,{"phase":"committed"})
    except Exception:
        restore_memory()
        with store.lock:
            recover(home)
            store.state["prefs"]=record["prefs_before"]
        raise
    try:journal.unlink(missing_ok=True)
    except OSError:pass  # durable committed marker is authoritative
