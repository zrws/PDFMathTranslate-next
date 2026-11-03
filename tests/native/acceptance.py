"""Real native API + BabelDOC pipeline against a loopback-only LLM fixture.

No paid API, fake translator implementation, user home, or formal update feed.
"""
import argparse
import hashlib
import http.client
import json
import os
import secrets
import shutil
import subprocess
import sys
import threading
import time
import uuid
import psutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--ui-exe", type=Path)
    parser.add_argument("--packaged",action="store_true",help="Use payload source only, without repository overlay")
    args = parser.parse_args()
    args.runtime_root = args.runtime_root.resolve()
    args.asset_root = args.asset_root.resolve()
    if args.ui_exe: args.ui_exe = args.ui_exe.resolve()
    repo = Path(__file__).resolve().parents[2]
    evidence = args.evidence_root.resolve()
    if evidence.exists(): raise RuntimeError("evidence exists; refuse reuse")
    evidence.mkdir(parents=True)
    home = repo/".local"/("native-acceptance-"+uuid.uuid4().hex)
    (home/"work").mkdir(parents=True)
    shutil.copytree(args.asset_root, home/".cache/babeldoc")
    python = next((args.runtime_root/"uv-python").glob("cpython-3.*.*-windows-x86_64-none/python.exe"))
    packages = args.runtime_root/"uv-tools/pdf2zh-next/Lib/site-packages"
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("PDF2ZH_", "BABELDOC_")): env.pop(key)
    env.update(PYTHONPATH=str(repo/"source")+os.pathsep+str(packages), PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1", PYTHONNOUSERSITE="1", PDF2ZH_HOME=str(home), PDF2ZH_LEGACY_ROOT=str(repo), NO_PROXY="127.0.0.1,localhost,::1", HTTP_PROXY="http://127.0.0.1:9", HTTPS_PROXY="http://127.0.0.1:9", ALL_PROXY="http://127.0.0.1:9")
    if args.packaged:env["PYTHONPATH"]=str(packages)
    for key, path in {"HOME":home,"USERPROFILE":home,"APPDATA":home/"AppData/Roaming","LOCALAPPDATA":home/"AppData/Local","TEMP":home/"tmp","TMP":home/"tmp","XDG_CACHE_HOME":home/".cache"}.items(): path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
    for key in ("SSL_CERT_DIR", "SSL_CERT_FILE"): env.pop(key, None)
    sample = home/"科学论文验收.pdf"
    generator = "import pymupdf,sys;d=pymupdf.open();p=d.new_page();p.insert_textbox(pymupdf.Rect(60,80,530,230),'Scientific document translation\\n\\nThis local acceptance document checks paragraph translation, page layout and scientific notation. The original engine must preserve the page structure.',fontsize=13,fontname='helv');p.insert_text((70,280),'E = m c^2',fontsize=16,fontname='tiit');d.save(sys.argv[1]);d.close()"
    subprocess.run([str(python), "-c", generator, str(sample)], env=env, cwd=home/"work", check=True, capture_output=True)
    calls = []
    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            messages = body.get("messages", [])
            text = "\n".join(str(m.get("content", "")) for m in messages)
            calls.append({"ts":time.time(),"path":self.path,"model":body.get("model"),"text_length":len(text)})
            translation="E = m c^2" if "E = m c^2" in text else "科学文档保留公式与页面结构。本地验收使用真实的排版和翻译流程。"
            response = {"id":"local-fixture", "object":"chat.completion", "created":int(time.time()), "model":"local-test-model", "choices":[{"index":0,"message":{"role":"assistant","content":translation},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":18,"total_tokens":30}}
            data = json.dumps(response, ensure_ascii=False).encode()
            self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(data)));self.end_headers();self.wfile.write(data)
    provider = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    threading.Thread(target=provider.serve_forever,daemon=True).start()
    mock_url = f"http://127.0.0.1:{provider.server_port}/v1"
    token = secrets.token_hex(32)
    stderr = (evidence/"control-stderr.txt").open("wb")
    child = subprocess.Popen([str(python),"-u","-m","pdf2zh_next.desktop.server"], env=env,cwd=home/"work",stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr,creationflags=0x08000000)
    child.stdin.write((json.dumps({"token":token,"downloads":str(home/"exports")})+"\n").encode());child.stdin.flush()
    hello = json.loads(child.stdout.readline())
    port = hello["port"]
    measurements=[];measurement_stop=threading.Event()
    def measure():
        while not measurement_stop.is_set():
            records=[]
            try:
                parent=psutil.Process(child.pid)
                for process in [parent]+parent.children(recursive=True):
                    try:
                        memory=process.memory_info();cpu=process.cpu_times();io=process.io_counters()
                        records.append({"pid":process.pid,"created":process.create_time(),"exe":process.exe(),"name":process.name(),"private_bytes":memory.private,"working_set_bytes":memory.rss,"threads":process.num_threads(),"cpu_seconds":cpu.user+cpu.system,"read_bytes":io.read_bytes,"write_bytes":io.write_bytes})
                    except (psutil.NoSuchProcess,psutil.AccessDenied):pass
            except psutil.NoSuchProcess:pass
            measurements.append({"ts":time.time(),"processes":records})
            measurement_stop.wait(.25)
    measurement_thread=threading.Thread(target=measure,daemon=True);measurement_thread.start()
    rows = []; events = []; event_stop = threading.Event(); connection = None
    def check(name, passed, detail=None):
        rows.append({"case":name,"passed":bool(passed),"detail":detail})
        if not passed: raise AssertionError(name+": "+str(detail))
    def request(method,path,body=None,headers=None,auth=True):
        conn=http.client.HTTPConnection("127.0.0.1",port,timeout=40)
        head={"Authorization":"Bearer "+token} if auth else {}
        if headers: head.update(headers)
        if body is not None and not isinstance(body,bytes): body=json.dumps(body).encode();head["Content-Type"]="application/json"
        conn.request(method,path,body,head);response=conn.getresponse();data=response.read();status=response.status;resp_headers=dict(response.getheaders());conn.close()
        if resp_headers.get("content-type", "").startswith("application/json"): data=json.loads(data)
        return status,data,resp_headers
    def poll(test, timeout=300):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            value=test()
            if value:return value
            time.sleep(.15)
        raise TimeoutError("acceptance condition timed out")
    def upload(path):
        boundary="native-"+uuid.uuid4().hex
        data=(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="sample.pdf"\r\nContent-Type: application/pdf\r\n\r\n').encode()+path.read_bytes()+f"\r\n--{boundary}--\r\n".encode()
        return request("POST","/api/files",data,{"Content-Type":"multipart/form-data; boundary="+boundary})
    def subscribe():
        nonlocal connection
        connection=http.client.HTTPConnection("127.0.0.1",port,timeout=30)
        connection.request("GET","/api/events",headers={"Authorization":"Bearer "+token})
        stream=connection.getresponse()
        try:
            while not event_stop.is_set():
                line=stream.readline()
                if not line:return
                if line.startswith(b"data: "):
                    events.append(json.loads(line[6:]))
        except (OSError, AttributeError):
            if not event_stop.is_set(): raise
    passed=False
    try:
        poll(lambda: request("GET","/api/health")[0]==200,30)
        check("health authenticated",request("GET","/api/health")[1]["control_ready"])
        check("health rejects missing bearer",request("GET","/api/health",auth=False)[0]==401)
        check("host rejects spoof",request("GET","/api/health",headers={"Host":"attacker.invalid"})[0]==403)
        check("origin rejects cross-site",request("GET","/api/health",headers={"Origin":"https://attacker.invalid"})[0]==403)
        poll(lambda:request("GET","/api/assets/status")[1]["state"]=="ready",40)
        threading.Thread(target=subscribe,daemon=True).start()
        poll(lambda:bool(events),10)
        check("initial SSE snapshot",events[0]["type"]=="snapshot" and events[0]["data"]["last_event_id"]==events[0]["event_id"])
        status,setting,_=request("PUT","/api/settings",{"service":"OpenAI","api_key":"local-fixture-only","base_url":mock_url,"model":"local-test-model","qps":100,"resource_tier":"balanced"})
        check("settings actual capped policy",status==200 and setting["effective_policy"]["api_qps_cap"]==4 and setting["effective_policy"]["document_concurrency"]==1)
        check("invalid settings rejected",request("PUT","/api/settings",{"qps":-1})[0]==400)
        check("settings failure preserves value",request("GET","/api/settings")[1]["requested_qps"]==100)
        status,file,_=upload(sample);check("real PDF upload",status==200 and file["page_count"]==1,file)
        status,png,_=request("GET",f'/api/files/{file["file_id"]}/preview?page=1&width=50000');check("bounded preview PNG",status==200 and png[:8]==b"\x89PNG\r\n\x1a\n")
        (evidence/"source-preview.png").write_bytes(png)
        payload={"file_id":file["file_id"],"lang_in":"en","lang_out":"zh-CN","no_dual":False,"no_mono":False,"auto_term_extraction":False,"export_dir":str(home/"exports")}
        key=str(uuid.uuid4());status,task,_=request("POST","/api/tasks",payload,{"Idempotency-Key":key});check("real task accepted",status==200,task)
        status,replay,_=request("POST","/api/tasks",payload,{"Idempotency-Key":key});check("create replay one task",status==200 and replay["id"]==task["id"])
        check("same key different language conflict",request("POST","/api/tasks",{**payload,"lang_out":"ja"},{"Idempotency-Key":key})[0]==409)
        def final():
            current=request("GET","/api/tasks/"+task["id"])[1]
            return current if current["status"] in {"done","failed","cancelled"} else None
        final_task=poll(final)
        (evidence/"task-final.json").write_text(json.dumps(final_task,ensure_ascii=False,indent=2),encoding="utf-8")
        check("genuine BabelDOC produced both outputs",final_task["status"]=="done" and set(final_task["outputs"])>={"dual","mono"},final_task.get("error"))
        check("real loopback provider used",len(calls)>=2,len(calls))
        status,preview,_=request("GET",f'/api/tasks/{task["id"]}/preview?kind=dual&page=2');check("translated output preview",status==200 and preview[:8]==b"\x89PNG\r\n\x1a\n")
        (evidence/"translated-preview.png").write_bytes(preview)
        export_id=str(uuid.uuid4());body={"directory":str(home/"exports"),"export_id":export_id}
        status,saved,_=request("POST",f'/api/tasks/{task["id"]}/export',body);check("actual export saved",status==200 and len(saved["saved_paths"])==2,saved)
        status,again,_=request("POST",f'/api/tasks/{task["id"]}/export',body);check("export replay no duplicate",status==200 and again["saved_paths"]==saved["saved_paths"])
        status,versioned,_=request("POST",f'/api/tasks/{task["id"]}/export',{**body,"export_id":str(uuid.uuid4())});check("second export versions",status==200 and len(versioned["saved_paths"])==4)
        for kind in ("mono","dual"):
            status,pdf,_=request("GET",f'/api/tasks/{task["id"]}/download?kind={kind}');check("download "+kind,status==200 and pdf.startswith(b"%PDF-"));(evidence/(kind+".pdf")).write_bytes(pdf)
        poll(lambda:any(e["type"]=="task.final" and e.get("task_id")==task["id"] for e in events),10)
        check("SSE final not dropped",any(e["type"]=="task.final" for e in events))
        check("no credential in events",not any("local-fixture-only" in json.dumps(e) or token in json.dumps(e) for e in events))
        config=request("GET",f'/api/tasks/{task["id"]}/configuration')[1]
        check("effective snapshot contains no API key",bool(config.get("settings_fingerprint")) and "local-fixture-only" not in json.dumps(config))
        old_fingerprint=final_task["options"]["settings_fingerprint"]
        request("PUT","/api/settings",{"custom_system_prompt":"new global prompt after original task","qps":2,"resource_tier":"eco"})
        replay=request("POST","/api/tasks",payload,{"Idempotency-Key":key})[1]
        check("create replay survives changed global settings",replay["id"]==task["id"] and replay["options"]["settings_fingerprint"]==old_fingerprint)
        first=request("POST","/api/tasks",payload,{"Idempotency-Key":str(uuid.uuid4())})[1]
        second=request("POST","/api/tasks",payload,{"Idempotency-Key":str(uuid.uuid4())})[1]
        cancelled=request("POST",f'/api/tasks/{second["id"]}/cancel',{})[1]
        check("queued cancellation is terminal",cancelled["status"]=="cancelled")
        original_fp=second["options"]["settings_fingerprint"]
        request("PUT","/api/settings",{"custom_system_prompt":"different prompt must not affect retry","qps":8,"resource_tier":"performance"})
        retry_key=str(uuid.uuid4())
        retried=request("POST",f'/api/tasks/{second["id"]}/retry',{}, {"Idempotency-Key":retry_key})[1]
        check("retry freezes original full configuration",retried["parent_task_id"]==second["id"] and retried["options"]["settings_fingerprint"]==original_fp)
        replay_retry=request("POST",f'/api/tasks/{second["id"]}/retry',{}, {"Idempotency-Key":retry_key})[1]
        check("retry lost-response key stable",replay_retry["id"]==retried["id"])
        request("POST",f'/api/tasks/{first["id"]}/cancel',{})
        request("POST",f'/api/tasks/{retried["id"]}/cancel',{})
        poll(lambda:all(t["status"] in {"done","failed","cancelled"} for t in request("GET","/api/tasks")[1]),20)
        request("DELETE","/api/tasks")
        replay=request("POST","/api/tasks",payload,{"Idempotency-Key":key})[1]
        check("clear history preserves create tombstone",replay["id"]==task["id"] and replay["status"]=="done")
        replay_retry=request("POST",f'/api/tasks/{second["id"]}/retry',{}, {"Idempotency-Key":retry_key})[1]
        check("clear history preserves retry tombstone",replay_retry["id"]==retried["id"])
        if args.ui_exe:
            # The app performs tests inside its own real WPF view tree, not
            # Windows input automation. Loopback provider remains alive here.
            scenario=evidence/"ui-scenario.json"
            ui_root=repo/"docs/verification/native-desktop"/("p1-ui-flow-"+uuid.uuid4().hex[:10])
            scenario.write_text(json.dumps({"output_root":str(ui_root),"sample":str(sample),"mock_base_url":mock_url}),encoding="utf-8")
            ui=subprocess.Popen([str(args.ui_exe),"--ui-test",str(scenario)],env=env)
            try: code=ui.wait(240)
            except subprocess.TimeoutExpired: ui.kill();code=-1
            check("native WPF integration flow",code==0,{"actual_exit":code,"evidence_root":str(ui_root)})
        passed=True
    finally:
        event_stop.set()
        if connection:connection.close()
        child.stdin.close()
        try: child.wait(15)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill","/PID",str(child.pid),"/T","/F"],capture_output=True);child.wait(10)
        stderr.close();provider.shutdown()
        measurement_stop.set();measurement_thread.join(2)
        (evidence/"process-samples.json").write_text(json.dumps({"scope":"real native API process tree, 250ms sampling, includes pipeline and previews; GPU counters not measured","samples":measurements},ensure_ascii=False),encoding="utf-8")
        (evidence/"events.jsonl").write_text("".join(json.dumps(e,ensure_ascii=False)+"\n" for e in events),encoding="utf-8")
        report={"passed":passed,"checks":rows,"home":str(home),"control_pid":child.pid,"control_actual_exit":child.returncode,"provider_calls":calls,"mode":"real BabelDOC + loopback LLM fixture; commercial translation quality unverified"}
        (evidence/"result.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"passed":passed,"checks":len(rows),"evidence":str(evidence)},ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__": raise SystemExit(main())
