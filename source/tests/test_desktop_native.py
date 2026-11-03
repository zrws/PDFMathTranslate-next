import concurrent.futures
import json
import threading
import uuid
from pathlib import Path

import pytest

from pdf2zh_next.desktop.exports import Exports
from pdf2zh_next.desktop.policy import effective_policy
from pdf2zh_next.desktop.runtime import DataOwner, migrate_config
from pdf2zh_next.desktop.storage import Store, file_identity


@pytest.fixture
def store(tmp_path): return Store(tmp_path/"home", tmp_path/"downloads")


def new_task(store, tmp_path, key="request", marker="content"):
    path = tmp_path/"input.pdf"
    path.write_bytes(b"%PDF-1.7 source")
    file = {"filename": "科学论文.pdf", "path": str(path), "sha256": "source", "page_count": 1}
    options = {"lang_in": "en", "lang_out": "zh-CN"}
    return store.create(key, marker, file, options)[0]


def completed(store, tmp_path):
    task = new_task(store, tmp_path)
    out = tmp_path/"output.pdf"; out.write_bytes(b"%PDF-1.7 real output fixture\n")
    store.start(task["id"])
    store.update(task["id"], status="done", progress=100, outputs={"dual": {"path": str(out), "output_revision": 1, **file_identity(out)}})
    return store.get(task["id"]), out


def test_concurrent_idempotency_and_conflict(store, tmp_path):
    task = new_task(store, tmp_path)
    file = {"filename": task["filename"], "path": task["file_path"], "sha256": "source", "page_count": 1}
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(lambda _: store.create("request", "content", file, task["options"]), range(40)))
    assert {row[0]["id"] for row in results} == {task["id"]}
    assert all(not row[1] for row in results)
    with pytest.raises(ValueError): store.create("request", "different", file, task["options"])


def test_cancel_start_race_has_one_legal_outcome(store, tmp_path):
    for number in range(40):
        task = new_task(store, tmp_path, str(number))
        gate = threading.Barrier(2)
        def start(): gate.wait(); return store.start(task["id"])
        def cancel(): gate.wait(); return store.cancel(task["id"])
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            first = pool.submit(start); second = pool.submit(cancel)
            started, cancelled = first.result(), second.result()
        current = store.get(task["id"])
        assert current["cancel_requested"]
        assert current["status"] == ("running" if started else "cancelled")


def test_clear_keeps_active_and_dedup_across_restart(store, tmp_path):
    done, _ = completed(store, tmp_path)
    active = new_task(store, tmp_path, "active")
    store.clear()
    assert [t["id"] for t in store.history()["active"]] == [active["id"]]
    assert not store.history()["history"]
    restored = Store(store.path.parent.parent, tmp_path/"downloads")
    replay, fresh = restored.create("request", "content", {"filename": done["filename"], "path": done["file_path"], "sha256": "source", "page_count": 1}, done["options"])
    assert not fresh and replay["id"] == done["id"] and replay["status"] == "done"
    assert restored.get(active["id"])["status"] == "failed"


def test_snapshot_watermark_and_concurrent_event_no_gap(store, tmp_path):
    task = new_task(store, tmp_path)
    snapshot = store.read_events(None)[0]
    watermark = snapshot["event_id"]
    assert snapshot["data"]["last_event_id"] == watermark
    store.update(task["id"], persist=True, message="new revision")
    events = store.read_events((store.instance_id, watermark))
    assert len(events) == 1 and events[0]["data"]["message"] == "new revision"
    store.clear()
    last = store.events[-1]
    assert last["type"] == "snapshot" and last["data"]["last_event_id"] == last["event_id"]


def test_overflow_restart_and_late_progress(store, tmp_path):
    task, out = completed(store, tmp_path)
    revision = task["revision"]
    store.update(task["id"], status="running", progress=2)
    assert store.get(task["id"])["revision"] == revision
    for value in range(1030): store.emit("settings.updated", {"value": value})
    assert store.read_events((store.instance_id, 0))[0]["type"] == "resync"
    assert store.read_events(("old-instance", 99999))[0]["type"] == "snapshot"


def test_history_pages_never_drop_active(store, tmp_path):
    for n in range(56):
        task = new_task(store, tmp_path, str(n))
        store.cancel(task["id"])
    active = new_task(store, tmp_path, "active")
    page = store.history(limit=50)
    more = store.history(page["next_cursor"], 50)
    assert len(page["history"]) == 50 and len(more["history"]) == 6
    assert {x["id"] for x in page["history"]}.isdisjoint(x["id"] for x in more["history"])
    assert page["active"][0]["id"] == more["active"][0]["id"] == active["id"]


def test_failed_persist_rolls_back_creation(store, tmp_path, monkeypatch):
    def full(): raise OSError("disk full")
    monkeypatch.setattr(store, "_persist", full)
    with pytest.raises(OSError): new_task(store, tmp_path)
    assert not store.state["tasks"] and not store.state["keys"]


def test_exports_versions_idempotency_and_no_overwrite(store, tmp_path):
    task, out = completed(store, tmp_path)
    exports = Exports(store); destination = tmp_path/"用户导出"
    first_id = str(uuid.uuid4())
    first = exports.save(task["id"], str(destination), first_id)
    assert len(first["saved_paths"]) == 1
    path = Path(first["saved_paths"][0]); assert path.name == "科学论文_双语.pdf"
    original = path.read_bytes()
    again = exports.save(task["id"], str(destination), first_id)
    assert again["saved_paths"] == first["saved_paths"]
    with concurrent.futures.ThreadPoolExecutor(3) as pool:
        list(pool.map(lambda _: exports.save(task["id"], str(destination), str(uuid.uuid4())), range(3)))
    current = store.get(task["id"])
    assert len(current["saved_paths"]) == 4 and path.read_bytes() == original
    assert {Path(p).name for p in current["saved_paths"]} == {"科学论文_双语.pdf", "科学论文_双语_v2.pdf", "科学论文_双语_v3.pdf", "科学论文_双语_v4.pdf"}
    assert not list(destination.rglob("*.partial")) and not list(destination.rglob("*.reserve"))


@pytest.mark.parametrize("condition", ["renamed", "truncated", "missing", "offline"])
def test_receipts_content_identity_and_staging_retention(store, tmp_path, condition):
    task, out = completed(store, tmp_path)
    final = tmp_path/"论文_终稿.pdf"
    if condition == "renamed": final.write_bytes(out.read_bytes())
    elif condition == "truncated": final.write_bytes(b"corrupted")
    elif condition == "offline": final = tmp_path/"unavailable-drive"/"result.pdf"
    output = task["outputs"]["dual"]
    payload = {"export_id": str(uuid.uuid4()), "task_id": task["id"], "kind": "dual", "output_revision": 1, "saved_path": str(final), **{k: output[k] for k in ("size_bytes", "sha256")}}
    exports = Exports(store)
    record = exports.receipt(payload)
    assert record["status"] == ("verified" if condition == "renamed" else "pending_verification")
    assert out.is_file()
    assert exports.receipt(payload) == record
    with pytest.raises(ValueError): exports.receipt({**payload, "saved_path": str(tmp_path/"other.pdf")})


def test_export_recovers_after_lost_response(store, tmp_path):
    task, out = completed(store, tmp_path)
    key = str(uuid.uuid4()); exports = Exports(store)
    result = exports.save(task["id"], str(tmp_path/"exports"), key)
    restarted = Store(store.path.parent.parent, tmp_path/"downloads")
    retry = Exports(restarted).save(task["id"], str(tmp_path/"exports"), key)
    assert retry["saved_paths"] == result["saved_paths"]
    assert len(list((tmp_path/"exports").rglob("*.pdf"))) == 1


def test_ownership_and_migration_are_non_destructive(tmp_path):
    owner = DataOwner(tmp_path/"home")
    try:
        with pytest.raises(OSError): DataOwner(tmp_path/"home")
    finally: owner.close()
    original = tmp_path/"old/home/.config/pdf2zh/config.v3.toml"
    original.parent.mkdir(parents=True); original.write_text("old config", encoding="utf-8")
    home = tmp_path/"new"
    migrate_config(home, tmp_path/"old")
    target = home/".config/pdf2zh/config.v3.toml"
    assert target.read_text(encoding="utf-8") == original.read_text(encoding="utf-8")
    target.write_text("new user setting", encoding="utf-8")
    migrate_config(home, tmp_path/"old")
    assert target.read_text(encoding="utf-8") == "new user setting" and original.read_text(encoding="utf-8") == "old config"


def test_policy_separates_local_remote_and_document_limits():
    eco = effective_policy("eco", 100)
    balanced = effective_policy("balanced", 1)
    fast = effective_policy("performance", 100)
    assert (eco["api_qps_cap"], balanced["api_qps_cap"], fast["api_qps_cap"]) == (2, 1, 8)
    assert all(p["document_concurrency"] == p["preview_concurrency"] == 1 and not p["gpu"] for p in (eco, balanced, fast))


def test_pending_receipt_revalidates_same_identity(store,tmp_path):
    task,out=completed(store,tmp_path);final=tmp_path/"恢复后的结果.pdf";identity=task["outputs"]["dual"]
    payload={"export_id":str(uuid.uuid4()),"task_id":task["id"],"kind":"dual","output_revision":1,"saved_path":str(final),**{k:identity[k] for k in ("size_bytes","sha256")}}
    exports=Exports(store)
    assert exports.receipt(payload)["status"]=="pending_verification"
    final.write_bytes(out.read_bytes())
    assert exports.receipt(payload)["status"]=="verified"
    final.write_bytes(b"corrupted")
    assert exports.receipt(payload)["status"]=="pending_verification" and out.exists()


def test_slow_export_does_not_hold_task_state_lock(store,tmp_path,monkeypatch):
    task,out=completed(store,tmp_path);exports=Exports(store);entered=threading.Event();release=threading.Event()
    original=exports._copy
    def slow(*args):entered.set();assert release.wait(3);return original(*args)
    monkeypatch.setattr(exports,"_copy",slow)
    with concurrent.futures.ThreadPoolExecutor(1) as pool:
        running=pool.submit(exports.save,task["id"],str(tmp_path/"exports"),str(uuid.uuid4()))
        assert entered.wait(3)
        assert store.lock.acquire(timeout=.5)
        store.lock.release();release.set();running.result()


def test_effective_snapshot_keeps_prompt_and_owned_glossary_but_not_credentials(tmp_path):
    from pdf2zh_next.desktop.snapshots import freeze
    from types import SimpleNamespace
    source=tmp_path/"terms.csv";source.write_text("science,科学\n",encoding="utf-8")
    value={"basic":{"input_files":[]},"translation":{"output":"old","glossaries":str(source),"custom_system_prompt":"original prompt"},"translate_engine_settings":{"openai_api_key":"not-a-real-secret","openai_model":"original-model"}}
    class Settings:
        translation=SimpleNamespace(glossaries=str(source))
        def model_dump(self,**kwargs):return json.loads(json.dumps(value))
    frozen=freeze(Settings(),tmp_path/"home")
    assert "not-a-real-secret" not in json.dumps(frozen)
    assert frozen["settings_snapshot"]["translation"]["custom_system_prompt"]=="original prompt"
    copy=Path(frozen["glossary_fingerprints"][0]["path"])
    source.write_text("changed,变化",encoding="utf-8")
    assert copy.read_text(encoding="utf-8")=="science,科学\n"


def test_settings_transaction_rolls_back_both_stores_and_recovers_crash(store,tmp_path,monkeypatch):
    from pdf2zh_next.desktop.settings_transaction import commit,recover
    import base64
    home=store.path.parent.parent;config=home/".config/pdf2zh/config.v3.toml";config.parent.mkdir(parents=True);config.write_bytes(b"old config")
    old_prefs=store.prefs();original=store._persist
    def fail():raise OSError("disk full after config commit")
    monkeypatch.setattr(store,"_persist",fail)
    with pytest.raises(OSError):commit(home,store,lambda:config.write_bytes(b"new config"),lambda:None,{"resource_tier":"eco"})
    assert config.read_bytes()==b"old config" and store.prefs()==old_prefs
    monkeypatch.setattr(store,"_persist",original)
    journal=home/"config/settings-transaction.private.json"
    journal.write_text(json.dumps({"phase":"prepared","config_before":base64.b64encode(b"old config").decode(),"prefs_before":old_prefs}),encoding="utf-8")
    config.write_bytes(b"partial new config");recover(home)
    assert config.read_bytes()==b"old config" and not journal.exists()


def test_every_real_password_field_is_removed_in_both_engine_sections(tmp_path):
    from types import SimpleNamespace
    from pdf2zh_next.desktop.snapshots import freeze
    from pdf2zh_next.config.translate_engine_model import GUI_PASSWORD_FIELDS
    sentinels={name:"secret-fixture-"+name for name in GUI_PASSWORD_FIELDS}
    class Settings:
        translation=SimpleNamespace(glossaries=None)
        def model_dump(self,**kwargs):return {"basic":{},"translation":{},"translate_engine_settings":dict(sentinels),"term_extraction_settings":dict(sentinels)}
    frozen=freeze(Settings(),tmp_path)
    encoded=json.dumps(frozen)
    assert all(value not in encoded for value in sentinels.values())
    for section in ("translate_engine_settings","term_extraction_settings"):
        assert all(frozen["settings_snapshot"][section][name] is None for name in GUI_PASSWORD_FIELDS)
        assert all([section,name] in frozen["credential_fields"] for name in GUI_PASSWORD_FIELDS)


def test_lost_export_response_remains_replayable_after_clear_history(store,tmp_path):
    task,_=completed(store,tmp_path);key=str(uuid.uuid4());destination=str(tmp_path/"exports")
    original=Exports(store).save(task["id"],destination,key)
    latest=Exports(store).save(task["id"],destination,str(uuid.uuid4()))
    for record in store.state["keys"].values():record["ts"]-=90000
    store.clear()
    assert store.get(task["id"]) is None
    restarted=Store(store.path.parent.parent,tmp_path/"downloads")
    replay=Exports(restarted).save(task["id"],destination,key)
    assert replay["saved_paths"]==latest["saved_paths"] and len(replay["saved_paths"])==2
    assert len(list((tmp_path/"exports").rglob("*.pdf")))==2


def test_failed_settings_recovery_preserves_journal_and_blocks_new_commit(store,tmp_path,monkeypatch):
    from pdf2zh_next.desktop import settings_transaction as transaction
    home=store.path.parent.parent;config=home/".config/pdf2zh/config.v3.toml";config.parent.mkdir(parents=True);config.write_bytes(b"original")
    original_persist=store._persist
    def fail_persist():raise OSError("simulated disk full")
    def fail_recovery(*args):raise OSError("simulated rollback write failure")
    monkeypatch.setattr(store,"_persist",fail_persist);monkeypatch.setattr(transaction,"atomic_bytes",fail_recovery)
    with pytest.raises(OSError):transaction.commit(home,store,lambda:config.write_bytes(b"partial"),lambda:None,{"resource_tier":"eco"})
    journal=home/"config/settings-transaction.private.json";before=journal.read_bytes()
    with pytest.raises(ValueError):transaction.commit(home,store,lambda:None,lambda:None,{})
    assert journal.read_bytes()==before


def test_engine_drains_finish_even_when_child_exits_before_collector(store,tmp_path,monkeypatch):
    from pdf2zh_next.desktop.engine import Engine
    import queue,time
    task=new_task(store,tmp_path);home=store.path.parent.parent
    output=home/"work/outputs"/task["id"]/"actual.pdf";output.parent.mkdir(parents=True);output.write_bytes(b"%PDF fixture")
    class Child:
        returncode=0
        def __init__(self,*args,**kwargs):
            self.lines=queue.Queue();self.stdout=self;self.stdin=self
        def write(self,data):
            if data.startswith('{'):
                prefix="PDF2ZH_EVENT "+json.loads(data)["event_nonce"]+" "
                self.lines.put(prefix+json.dumps({"type":"finish","outputs":{"dual":str(output)}})+"\n");self.lines.put(prefix+"null\n");self.lines.put("")
        def flush(self):pass
        def close(self):pass
        def readline(self,*args):time.sleep(.06);return self.lines.get(timeout=2)
        def poll(self):return 0
        def wait(self,*args):return 0
    monkeypatch.setattr("pdf2zh_next.desktop.engine.subprocess.Popen",Child)
    engine=Engine(home,store)
    try:engine.run(task["id"],{},{});assert store.get(task["id"])["status"]=="done"
    finally:engine.close()


def test_engine_cancel_interrupts_blocked_boot_stdin_and_queue_continues(store,tmp_path,monkeypatch):
    from pdf2zh_next.desktop.engine import Engine
    import queue,subprocess,time
    first=new_task(store,tmp_path,"blocked");second=new_task(store,tmp_path,"next");home=store.path.parent.parent
    output=home/"work/outputs"/second["id"]/"actual.pdf";output.parent.mkdir(parents=True);output.write_bytes(b"%PDF fixture")
    entered=threading.Event();created=[]
    class Child:
        def __init__(self,*args,**kwargs):
            self.blocked=not created;created.append(self);self.returncode=None;self.dead=threading.Event();self.lines=queue.Queue();self.stdin=self;self.stdout=self
        def write(self,data):
            if not data.startswith('{'):return
            if self.blocked:entered.set();self.dead.wait(3);return
            prefix="PDF2ZH_EVENT "+json.loads(data)["event_nonce"]+" "
            self.lines.put(prefix+json.dumps({"type":"finish","outputs":{"dual":str(output)}})+"\n");self.lines.put(prefix+"null\n");self.lines.put("");self.returncode=0
        def flush(self):pass
        def close(self):pass
        def readline(self,*args):
            if self.blocked:self.dead.wait(3);return ""
            return self.lines.get(timeout=3)
        def poll(self):return self.returncode
        def wait(self,timeout=None):
            if self.returncode is None:raise subprocess.TimeoutExpired("controlled child",timeout)
            return self.returncode
        def kill(self):self.returncode=-1;self.dead.set()
    monkeypatch.setattr("pdf2zh_next.desktop.engine.subprocess.Popen",Child)
    engine=Engine(home,store)
    try:
        engine.submit(first["id"],{},{});assert entered.wait(2)
        store.cancel(first["id"]);engine.submit(second["id"],{},{})
        end=time.monotonic()+5
        while time.monotonic()<end and store.get(second["id"])["status"] not in {"done","failed"}:time.sleep(.05)
        assert store.get(first["id"])["status"]=="cancelled"
        assert store.get(second["id"])["status"]=="done" and created[0].dead.is_set()
    finally:engine.close()


def test_committed_settings_survive_journal_cleanup_failure(store,tmp_path,monkeypatch):
    from pdf2zh_next.desktop import settings_transaction as transaction
    home=store.path.parent.parent;config=home/".config/pdf2zh/config.v3.toml";config.parent.mkdir(parents=True);config.write_bytes(b"old")
    original=Path.unlink;failed=[]
    def fail_once(path,*args,**kwargs):
        if path.name=="settings-transaction.private.json" and not failed:failed.append(True);raise PermissionError("simulated cleanup lock")
        return original(path,*args,**kwargs)
    monkeypatch.setattr(Path,"unlink",fail_once)
    transaction.commit(home,store,lambda:config.write_bytes(b"committed"),lambda:None,{"resource_tier":"eco"})
    assert config.read_bytes()==b"committed" and store.prefs()["resource_tier"]=="eco"
    transaction.recover(home)
    assert config.read_bytes()==b"committed"


def test_old_auto_update_opt_out_is_preserved_and_native_preference_wins(tmp_path):
    home=tmp_path/"home";prefs=home/".config/pdf2zh/ui-prefs.json";prefs.parent.mkdir(parents=True);prefs.write_text('{"auto_update":false}',encoding="utf-8")
    store=Store(home,tmp_path/"downloads");assert store.prefs()["auto_update"] is False
    store.prefs({"auto_update":True})
    assert Store(home,tmp_path/"downloads").prefs()["auto_update"] is True


def test_cross_home_migration_keeps_old_update_opt_out(tmp_path):
    old=tmp_path/"old";original=old/"home/.config/pdf2zh/ui-prefs.json";original.parent.mkdir(parents=True);original.write_text('{"auto_update":false}',encoding="utf-8")
    home=tmp_path/"new";migrate_config(home,old)
    store=Store(home,tmp_path/"downloads");assert store.prefs()["auto_update"] is False
    assert original.read_text(encoding="utf-8")=='{"auto_update":false}'
    store.prefs({"auto_update":True});migrate_config(home,old)
    assert Store(home,tmp_path/"downloads").prefs()["auto_update"] is True
