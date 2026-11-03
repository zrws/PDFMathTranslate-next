"""Independent one-run diagnosis. No app code imports and no locals dumps."""
import ctypes
from ctypes import wintypes
import hashlib,json,os,subprocess,sys,time
from pathlib import Path
import psutil

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[3]
RUNTIME=REPO/".local/native-runtime"
PYTHON=next((RUNTIME/"uv-python").glob("cpython-3.12.13-windows-x86_64-none/python.exe"))
SPY=REPO/".local/debug-tools/bin/py-spy.exe"
EVIDENCE=ROOT/"acceptance"
CONTROL_HOME=REPO/".local"/("independent-diag-control-"+ROOT.name.rsplit("-",1)[-1])
for path in [CONTROL_HOME,CONTROL_HOME/"work",CONTROL_HOME/"tmp",CONTROL_HOME/"roaming",CONTROL_HOME/"local",CONTROL_HOME/"cache"]:
    path.mkdir(parents=True,exist_ok=True)

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save(name,value):(ROOT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding="utf-8")
def background_metadata():
    rows=[]
    for path in (REPO/".local/p0-temp").glob("*"):
        if path.is_file() and ("native-build-r9" in path.name or "installer" in path.name or "pytest" in path.name and "current" in path.name):
            stat=path.stat();rows.append({"name":path.name,"size":stat.st_size,"mtime":stat.st_mtime})
    return rows
def identity(process):
    return {"pid":process.pid,"created":process.create_time(),"ppid":process.ppid(),"exe":process.exe(),"argv":process.cmdline()}
def alive_same(row):
    try:return abs(psutil.Process(row["pid"]).create_time()-row["created"])<.001
    except psutil.Error:return False

kernel=ctypes.WinDLL("kernel32",use_last_error=True)
kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD]
kernel.OpenProcess.restype=wintypes.HANDLE
kernel.CloseHandle.argtypes=[wintypes.HANDLE]
kernel.GetProcessTimes.argtypes=[wintypes.HANDLE,ctypes.POINTER(wintypes.FILETIME),ctypes.POINTER(wintypes.FILETIME),ctypes.POINTER(wintypes.FILETIME),ctypes.POINTER(wintypes.FILETIME)]
kernel.GetProcessTimes.restype=wintypes.BOOL
kernel.GetExitCodeProcess.argtypes=[wintypes.HANDLE,ctypes.POINTER(wintypes.DWORD)]
def pin(row):
    handle=kernel.OpenProcess(0x1000|0x100000,False,row["pid"])
    if not handle:raise OSError(ctypes.get_last_error(),"cannot pin owned process")
    values=[wintypes.FILETIME() for _ in range(4)]
    if not kernel.GetProcessTimes(handle,*[ctypes.byref(v) for v in values]):
        kernel.CloseHandle(handle);raise OSError("GetProcessTimes failed")
    created=((values[0].dwHighDateTime<<32)|values[0].dwLowDateTime)/10000000-11644473600
    if abs(created-row["created"])>.005:
        kernel.CloseHandle(handle);raise RuntimeError("PID identity changed")
    return handle

env=os.environ.copy()
for name in list(env):
    if name.startswith(("PDF2ZH_","BABELDOC_")):env.pop(name)
env.update(PYTHONPATH=str(RUNTIME/"uv-tools/pdf2zh-next/Lib/site-packages"),
           PYTHONUTF8="1",PYTHONDONTWRITEBYTECODE="1",PYTHONNOUSERSITE="1",
           HOME=str(CONTROL_HOME),USERPROFILE=str(CONTROL_HOME),APPDATA=str(CONTROL_HOME/"roaming"),
           LOCALAPPDATA=str(CONTROL_HOME/"local"),TEMP=str(CONTROL_HOME/"tmp"),TMP=str(CONTROL_HOME/"tmp"),
           XDG_CACHE_HOME=str(CONTROL_HOME/"cache"),NO_PROXY="127.0.0.1,localhost,::1",
           HTTP_PROXY="http://127.0.0.1:9",HTTPS_PROXY="http://127.0.0.1:9",ALL_PROXY="http://127.0.0.1:9")
for name in ("SSL_CERT_FILE","SSL_CERT_DIR"):env.pop(name,None)
argv=[str(PYTHON),"-u",str(REPO/"tests/native/acceptance.py"),"--runtime-root",str(RUNTIME),
      "--asset-root",str(REPO/".local/runtime/home/.cache/babeldoc"),"--evidence-root",str(EVIDENCE)]
if (ROOT/"plan.json").exists() or EVIDENCE.exists():raise RuntimeError("refuse reused diagnostic root")
tracked=[REPO/"tests/native/acceptance.py",REPO/"source/pdf2zh_next/desktop/engine.py",
         REPO/"source/pdf2zh_next/desktop/worker.py",SPY,Path(__file__)]
before={str(p):digest(p) for p in tracked}
started=time.time()
save("plan.json",{"argv":argv,"script_hashes":before,"started":started,"timeout_seconds":360,
  "stack_condition":"owned desktop.worker preparing/loading at age >=20s; repeat every 20s, max 5 per worker",
  "spy_options":["dump","--json","--full-filenames","--nonblocking"],
  "scope":"one existing loopback LLM acceptance; no UI; no locals/native/other-process dump",
  "parent_reported_load":"r9 clean full installer build and test installer compilation; concurrent pytest in failed original run",
  "background_logs":background_metadata()})
stdout=(ROOT/"acceptance.stdout.txt").open("wb");stderr=(ROOT/"acceptance.stderr.txt").open("wb")
child=subprocess.Popen(argv,cwd=REPO,env=env,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,creationflags=0x08000000)
owner=psutil.Process(child.pid);owner_identity=identity(owner)
save("owner.json",owner_identity)
known={};dumps=[];last_dump={};dump_counts={};timed_out=False
psutil.cpu_percent(interval=None)
monitor=(ROOT/"monitor.jsonl").open("w",encoding="utf-8")
try:
    while child.poll() is None:
        now=time.time()
        if now-started>360:timed_out=True;break
        rows=[];candidates=[]
        try:descendants=owner.children(recursive=True)
        except psutil.Error:descendants=[]
        for process in descendants:
            try:
                row=identity(process)
                if row["created"]<owner_identity["created"]-.01:continue
                known[(row["pid"],row["created"])]=row
                row["private_bytes"]=process.memory_full_info().private
                row["cpu_seconds"]=sum(process.cpu_times()[:2])
                rows.append(row)
                command=row["argv"]
                if "-m" in command and "pdf2zh_next.desktop.worker" in command and "--translate" in command:
                    if Path(row["exe"]).resolve()!=PYTHON.resolve():continue
                    home=Path(process.cwd()).resolve().parent
                    if not home.is_relative_to((REPO/".local").resolve()) or not home.name.startswith("native-acceptance-"):continue
                    state_path=home/"config/desktop-state.json"
                    state=json.loads(state_path.read_text(encoding="utf-8"))
                    active=[{k:t.get(k) for k in ("id","status","phase","stage","revision","created_at","finished_at")} for t in state["tasks"].values() if t["status"]=="running"]
                    row["tasks"]=active
                    if any(t["phase"]=="preparing" for t in active):candidates.append((process,row,active))
            except (psutil.Error,OSError,ValueError):continue
        monitor.write(json.dumps({"ts":now,"system_cpu_percent":psutil.cpu_percent(interval=None),"available_memory":psutil.virtual_memory().available,"owned_descendants":rows},ensure_ascii=False)+"\n");monitor.flush()
        for process,row,active in candidates:
            key=(row["pid"],row["created"])
            if now-row["created"]<20 or now-last_dump.get(key,0)<20 or dump_counts.get(key,0)>=5:continue
            # Recheck both descendant membership and image/creation identity, then
            # retain a process handle across py-spy so a terminated PID cannot recycle.
            try:
                current_ids={(p.pid,p.create_time()) for p in owner.children(recursive=True)}
                if key not in current_ids or not alive_same(row):continue
                handle=pin(row)
            except (psutil.Error,OSError,RuntimeError):continue
            try:
                command=[str(SPY),"dump","--pid",str(row["pid"]),"--json","--full-filenames","--nonblocking"]
                index=len(dumps)+1;stem=f"worker-{row['pid']}-stack-{index}"
                entry={"worker":row,"task_states":active,"argv":command,"started":time.time(),"no_locals":True}
                try:
                    out=subprocess.run(command,capture_output=True,timeout=12,cwd=ROOT,env=env,creationflags=0x08000000)
                    (ROOT/(stem+".stdout.json")).write_bytes(out.stdout);(ROOT/(stem+".stderr.txt")).write_bytes(out.stderr)
                    entry.update(actual_exit=out.returncode,stdout_sha256=hashlib.sha256(out.stdout).hexdigest(),stderr_sha256=hashlib.sha256(out.stderr).hexdigest())
                except subprocess.TimeoutExpired as exc:
                    (ROOT/(stem+".stdout.json")).write_bytes(exc.stdout or b"");(ROOT/(stem+".stderr.txt")).write_bytes(exc.stderr or b"")
                    entry.update(actual_exit=None,timeout=True)
                code=wintypes.DWORD();kernel.GetExitCodeProcess(handle,ctypes.byref(code))
                entry.update(ended=time.time(),worker_exit_code_after_dump=code.value)
                save(stem+".observed.json",entry);dumps.append(entry)
                print(json.dumps({"stack":stem,"pid":row["pid"],"actual_exit":entry.get("actual_exit"),"stage":[t["stage"] for t in active]}),flush=True)
                last_dump[key]=time.time();dump_counts[key]=dump_counts.get(key,0)+1
            finally:kernel.CloseHandle(handle)
        time.sleep(1)
finally:
    if child.poll() is None:
        try:owned=owner.children(recursive=True)
        except psutil.Error:owned=[]
        identities=[]
        for process in reversed(owned):
            try:
                row=identity(process);identities.append(row)
                if row["created"]>=owner_identity["created"]-.01:process.kill()
            except psutil.Error:pass
        if alive_same(owner_identity):child.kill()
        try:child.wait(15)
        except subprocess.TimeoutExpired:pass
        save("timeout-cleanup.json",{"only_owned_descendants":identities,"owner":owner_identity})
    stdout.close();stderr.close();monitor.close()
    remaining=[row for row in known.values() if alive_same(row)]
    after={str(p):digest(p) for p in tracked}
    save("observed.json",{"owner":owner_identity,"started":started,"ended":time.time(),"actual_exit":child.poll(),
      "timeout":timed_out,"stack_dumps":len(dumps),"remaining_owned":remaining,
      "hashes_unchanged":before==after,"hashes_after":after,"background_logs":background_metadata()})
print(json.dumps({"actual_exit":child.poll(),"stack_dumps":len(dumps),"timeout":timed_out,"remaining_owned":len(remaining),"evidence":str(ROOT)}),flush=True)
sys.exit(0 if child.returncode==0 and not timed_out and not remaining else 1)
