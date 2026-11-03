"""Real authenticated legacy bootstrap + cross-process home writer exclusion."""
import argparse,http.client,json,os,queue,secrets,socket,subprocess,sys,threading,time,uuid
from pathlib import Path


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--runtime-root',type=Path,required=True);parser.add_argument('--evidence-root',type=Path,required=True);args=parser.parse_args()
    repo=Path(__file__).resolve().parents[2];root=args.evidence_root.resolve();root.mkdir(parents=True,exist_ok=False)
    home=repo/'.local'/('compatibility-'+uuid.uuid4().hex);home.mkdir()
    runtime=args.runtime_root.resolve();python=next((runtime/'uv-python').glob('cpython-3.*.*-windows-x86_64-none/python.exe'))
    env=os.environ.copy();env.update(PYTHONPATH=str(repo/'source')+os.pathsep+str(runtime/'uv-tools/pdf2zh-next/Lib/site-packages'),PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1',PYTHONNOUSERSITE='1',PDF2ZH_HOME=str(home),PDF2ZH_LEGACY_ROOT=str(repo),HTTP_PROXY='http://127.0.0.1:9',HTTPS_PROXY='http://127.0.0.1:9',ALL_PROXY='http://127.0.0.1:9',NO_PROXY='127.0.0.1,localhost,::1')
    for key,folder in {'HOME':home,'USERPROFILE':home,'APPDATA':home/'appdata','LOCALAPPDATA':home/'local','TEMP':home/'tmp','TMP':home/'tmp','XDG_CACHE_HOME':home/'.cache'}.items():folder.mkdir(parents=True,exist_ok=True);env[key]=str(folder)
    with socket.socket() as reservation:reservation.bind(('127.0.0.1',0));port=reservation.getsockname()[1]
    token=secrets.token_hex(32);rows=[];passed=False;other_exit=None
    def check(name,value,detail=None):
        rows.append({'case':name,'passed':bool(value),'detail':detail})
        if not value:raise AssertionError(name)
    def request(path='/',auth=True,origin=None):
        conn=http.client.HTTPConnection('127.0.0.1',port,timeout=3);headers={'Authorization':'Bearer '+token} if auth else {}
        if origin:headers['Origin']=origin
        conn.request('GET',path,headers=headers);response=conn.getresponse();status=response.status;response.read();conn.close();return status
    error=(root/'legacy-stderr.txt').open('wb')
    child=subprocess.Popen([str(python),'-u','-m','pdf2zh_next.desktop.compatibility'],env=env,cwd=home,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=error,creationflags=0x08000000)
    child.stdin.write((json.dumps({'token':token,'port':port})+'\n').encode());child.stdin.flush()
    lines=queue.Queue();threading.Thread(target=lambda:lines.put(child.stdout.readline()),daemon=True).start()
    try:
        line=lines.get(timeout=35);check('legacy bootstrap ready marker',b'WebUI ready:' in line)
        deadline=time.monotonic()+30
        while time.monotonic()<deadline:
            try:
                if request()==200:break
            except (OSError,http.client.HTTPException):pass
            time.sleep(.1)
        check('authenticated legacy static UI',request()==200)
        check('browser without token rejected',request(auth=False)==401)
        check('authenticated legacy settings',request('/api/settings')==200)
        check('cross-origin request rejected',request('/api/settings',origin='https://example.test')==403)
        with (root/'writer-conflict-stderr.txt').open('wb') as conflict:
            other=subprocess.Popen([str(python),'-u','-m','pdf2zh_next.desktop.server'],env=env,cwd=home,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=conflict,creationflags=0x08000000)
            try:
                other.communicate((json.dumps({'token':secrets.token_hex(32),'downloads':str(home/'downloads')})+'\n').encode(),timeout=25)
                other_exit=other.returncode
                check('native entry refuses occupied legacy home',other_exit!=0,other_exit)
            finally:
                if other.poll() is None:other.kill();other.wait(5)
        passed=True
    finally:
        child.stdin.close()
        try:child.wait(15)
        except subprocess.TimeoutExpired:child.kill();child.wait(5);passed=False
        error.close()
        report={'passed':passed and child.returncode==0,'checks':rows,'home':str(home),'legacy_pid':child.pid,'legacy_actual_exit':child.returncode,'native_conflict_actual_exit':other_exit,'scope':'real legacy HTTP bootstrap and writer lock; WebView2 input and downloads not automated'}
        (root/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False));return 0 if report['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
