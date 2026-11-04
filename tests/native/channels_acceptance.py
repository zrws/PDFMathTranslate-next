"""Real WPF channels/batch workflow with owned PDFs and a loopback-only provider."""
import argparse,hashlib,json,os,shutil,subprocess,threading,time,uuid
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from owned_process import OwnedJob,identity,canonical,sample_owned
import psutil

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--ui-exe',type=Path,required=True)
    parser.add_argument('--runtime-root',type=Path,required=True)
    parser.add_argument('--asset-root',type=Path,required=True)
    parser.add_argument('--layout-only',action='store_true')
    parser.add_argument('--packaged',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[2];uid=uuid.uuid4().hex[:10]
    evidence=repo/'docs/verification/native-desktop'/('channels-workflow-'+uid);evidence.mkdir()
    sandbox=repo/'.local'/('channels-workflow-'+uid);sandbox.mkdir()
    home=sandbox/'home';home.mkdir()
    shutil.copytree(args.asset_root.resolve(),home/'.cache/babeldoc')
    runtime=args.runtime_root.resolve();packages=runtime/'uv-tools/pdf2zh-next/Lib/site-packages'
    python=next((runtime/'uv-python').glob('cpython-3.*.*-windows-x86_64-none/python.exe'))
    source=packages if args.packaged else repo/'source'
    env=os.environ.copy()
    for key in list(env):
        if key.startswith(('PDF2ZH_','BABELDOC_')):env.pop(key)
    env.update(PYTHONPATH=str(source)+os.pathsep+str(packages),PYTHONDONTWRITEBYTECODE='1',PYTHONNOUSERSITE='1',PYTHONUTF8='1',HTTP_PROXY='http://127.0.0.1:9',HTTPS_PROXY='http://127.0.0.1:9',ALL_PROXY='http://127.0.0.1:9',NO_PROXY='127.0.0.1,localhost,::1',PDF2ZH_HOME=str(home))
    for key,path in {'HOME':home,'USERPROFILE':home,'APPDATA':home/'AppData/Roaming','LOCALAPPDATA':home/'AppData/Local','TEMP':home/'tmp','TMP':home/'tmp','XDG_CACHE_HOME':home/'.cache'}.items():
        path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
    for key in ('SSL_CERT_FILE','SSL_CERT_DIR'):env.pop(key,None)
    samples=[]
    generator="""import pymupdf,sys
doc=pymupdf.open()
for i in range(int(sys.argv[2])):
 p=doc.new_page()
 p.insert_text((52,60),'Scientific paper page '+str(i+1),fontsize=16)
 p.insert_textbox(pymupdf.Rect(52,100,545,650),'Unique page '+str(i+1)+' marker. Scientific evidence must include every page, including page seven. The experiment compares a baseline with a bounded resource policy. Mathematical notation and paragraph order must survive translation.\\n\\nEach observation records its effective configuration and actual result.',fontsize=12)
 p.insert_text((52,740),'E = m c^2',fontsize=14)
doc.save(sys.argv[1])
"""
    for number,pages in enumerate((7,2,1),1):
        folder=sandbox/('source-'+str(number));folder.mkdir();path=folder/('论文'+str(number)+'.pdf')
        subprocess.run([str(python),'-c',generator,str(path),str(pages)],env=env,check=True,capture_output=True)
        samples.append(path)
    calls=[];slow_started=threading.Event();slow_released=threading.Event()
    class Provider(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def send_data(self,data,status=200,content_type='application/json'):
            raw=data if isinstance(data,bytes) else json.dumps(data,ensure_ascii=False).encode()
            try:self.send_response(status);self.send_header('Content-Type',content_type);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
            except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
        def do_GET(self):
            if self.path=='/probe-state':self.send_data(b'started' if slow_started.is_set() else b'waiting',content_type='text/plain');return
            if self.path=='/release-probe':slow_released.set();self.send_data(b'ok',content_type='text/plain');return
            if self.path.endswith('/models'):
                if self.path.startswith('/slow/'):slow_started.set();slow_released.wait(10)
                model='owned-model-b' if self.path.startswith('/b/') else 'owned-model-a'
                self.send_data({'data':[{'id':model,'object':'model'}]});return
            self.send_data({'error':'unknown fixture path'},404)
        def do_POST(self):
            body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            text='\n'.join(str(m.get('content','')) for m in body.get('messages',[]))
            prefix='b' if self.path.startswith('/b/') else 'a'
            is_probe='Please reply only OK.' in text
            valid=self.headers.get('Authorization')=='Bearer owned-ui-channel-secret-'+prefix.upper()
            calls.append({'prefix':prefix,'model':body.get('model'),'probe':is_probe,'authorization_match':valid,'text_length':len(text),'mentions_page_seven':'page 7' in text.lower() or 'page seven' in text.lower()})
            if not valid:self.send_data({'error':'owned fixture authentication rejected'},401);return
            value='OK' if is_probe else '科学论文译文保留公式与页面结构，逐页记录实验结果和有效配置。'
            self.send_data({'id':'owned-local-fixture','object':'chat.completion','created':int(time.time()),'model':body.get('model'),'choices':[{'index':0,'message':{'role':'assistant','content':value},'finish_reason':'stop'}],'usage':{'prompt_tokens':12,'completion_tokens':16,'total_tokens':28}})
    provider=ThreadingHTTPServer(('127.0.0.1',0),Provider)
    threading.Thread(target=provider.serve_forever,daemon=True).start()
    exe=args.ui_exe.resolve()
    profile={'PDF2ZH_APP_ROOT':str(repo),'PDF2ZH_RUNTIME_ROOT':str(runtime),'PDF2ZH_SOURCE_ROOT':str(source),'PDF2ZH_HOME':str(home)}
    (exe.parent/'development-run.json').write_text(json.dumps(profile,ensure_ascii=False),encoding='utf-8')
    scenario={'channels_batch':True,'workflow_layout_only':args.layout_only,'output_root':str(evidence/'ui'),'mock_base_url':f'http://127.0.0.1:{provider.server_port}/','samples':list(map(str,samples))}
    scenario_path=evidence/'scenario.json';scenario_path.write_text(json.dumps(scenario,ensure_ascii=False),encoding='utf-8')
    provenance_code="import hashlib,json,pathlib,pdf2zh_next;root=pathlib.Path(pdf2zh_next.__file__).parent;names=['desktop/server.py','desktop/channels.py','desktop/protected_config.py','desktop/runtime.py','desktop/settings_transaction.py','desktop/engine.py','desktop/exports.py','desktop/worker.py','desktop/snapshots.py','config/main.py','http_api.py'];print(json.dumps({'root':str(root),'files':[{'path':str(root/n),'sha256':hashlib.sha256((root/n).read_bytes()).hexdigest()} for n in names]},ensure_ascii=False))"
    probe=subprocess.run([str(python),'-c',provenance_code],env=env,cwd=sandbox,capture_output=True,check=True,text=True,encoding='utf-8')
    provenance=json.loads(probe.stdout)
    provenance.update(source_mode='packaged' if args.packaged else 'repository overlay',ui_exe_sha256=sha(exe),ui_dll_sha256=sha(exe.with_suffix('.dll')),driver_sha256=sha(__file__),ownership_helper_sha256=sha(Path(__file__).with_name('owned_process.py')),profile=profile,profile_sha256=sha(exe.parent/'development-run.json'),source_commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),samples=[{'path':str(p),'sha256':sha(p)} for p in samples])
    provenance['source_dirty']=bool(subprocess.check_output(['git','-C',str(repo),'status','--porcelain','--untracked-files=no'],text=True).strip())
    native=repo/'desktop/PDFMathTranslate.Desktop'
    provenance['native_source_files']=[{'path':str(p.relative_to(repo)).replace('\\','/'),'sha256':sha(p)} for p in sorted(native.iterdir()) if p.is_file() and (p.suffix in ('.cs','.xaml','.csproj') or p.name=='packages.lock.json')]
    (evidence/'provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding='utf-8')
    stdout=(evidence/'ui.stdout.txt').open('wb');stderr=(evidence/'ui.stderr.txt').open('wb')
    child=subprocess.Popen([str(exe),'--ui-test',str(scenario_path)],env=env,cwd=sandbox,stdout=stdout,stderr=stderr)
    job=None;stop=threading.Event();samples_out=[];measure_errors=[]
    code=None;timed_out=False;passed=False;error=None;started=time.time()
    try:
        job=OwnedJob(child);root_identity=identity(psutil.Process(child.pid))
        allowed={canonical(exe),canonical(python),canonical(python.with_name('pythonw.exe')),canonical(Path(os.environ['SystemRoot'])/'System32/conhost.exe')}
        def measure():
            try:
                while not stop.is_set():
                    records,rejected=sample_owned(root_identity,job,allowed)
                    samples_out.append({'ts':time.time(),'processes':records,'rejected_counts':rejected});stop.wait(.5)
            except Exception as exc:measure_errors.append(type(exc).__name__)
        observer=threading.Thread(target=measure,daemon=True);observer.start()
        while child.poll() is None:
            if time.time()-started>(180 if args.layout_only else 1500):
                timed_out=True;job.close();break
            time.sleep(.25)
        code=child.wait(10);stop.set();observer.join(10);job.close()
        result=json.loads((evidence/'ui/ui-result.json').read_text(encoding='utf-8-sig'))
        passed=code==0 and result.get('passed') is True and not measure_errors and not observer.is_alive()
        if passed and not args.layout_only:
            tasks=json.loads((evidence/'ui/actual-tasks.json').read_text(encoding='utf-8'))
            audit=[]
            import pymupdf
            for task in tasks:
                for kind,filename in task['outputs'].items():
                    path=Path(filename).resolve()
                    if not path.is_relative_to(home.resolve()):raise ValueError('Refuse output outside owned home')
                    with pymupdf.open(path) as doc:
                        item={'task_id':task['id'],'kind':kind,'pages':len(doc),'sha256':sha(path),'last_page_has_chinese':any('\u4e00'<=c<='\u9fff' for c in doc[-1].get_text())}
                    if task['filename']==samples[0].name and (item['pages']<7 or not item['last_page_has_chinese']):raise AssertionError('Seven-page output does not contain actual translated final page')
                    audit.append(item)
            (evidence/'pdf-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
            if len(tasks)!=4 or not all(c['authorization_match'] for c in calls):raise AssertionError('Batch count or channel authentication mismatch')
    except Exception as exc:error=type(exc).__name__+': '+str(exc);passed=False
    finally:
        stop.set()
        if job:job.close()
        if child.poll() is None:child.kill()
        code=child.wait(10);stdout.close();stderr.close();slow_released.set();provider.shutdown()
        identities={(p['pid'],p['created']):p['exe'] for row in samples_out for p in row['processes']}
        survivors=[]
        for (pid,created),image in identities.items():
            try:
                if psutil.Process(pid).create_time()==created and psutil.pid_exists(pid):survivors.append({'pid':pid,'created':created,'exe':image})
            except (psutil.NoSuchProcess,psutil.AccessDenied):pass
        passed=passed and not survivors and not timed_out
        (evidence/'process-samples.json').write_text(json.dumps({'scope':'kernel Job members with fresh identity/parent checks; own workflow processes only','samples':samples_out},ensure_ascii=False),encoding='utf-8')
        report={'passed':passed,'actual_exit':code,'timeout':timed_out,'error':error,'observer_errors':measure_errors,'surviving_identities':survivors,'provider_calls':calls,'source_mode':provenance['source_mode'],'provenance_sha256':sha(evidence/'provenance.json'),'layout_only':args.layout_only,'home':str(home),'started':started,'finished':time.time()}
        (evidence/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':passed,'evidence':str(evidence),'actual_exit':code,'error':error},ensure_ascii=False))
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
