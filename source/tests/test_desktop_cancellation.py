import asyncio
import hashlib
import http.client
import json
import socket
import subprocess
import sys
import threading
import time

from fastapi.testclient import TestClient

from pdf2zh_next.desktop import server
from pdf2zh_next.desktop.assets import Assets
from pdf2zh_next.desktop.preview_control import capture_process
from pdf2zh_next.desktop.storage import Store


def test_asset_cancel_before_download_thread_runs(tmp_path, monkeypatch):
    assets = Assets(tmp_path, Store(tmp_path, tmp_path/'downloads'))
    gate = threading.Event(); entered = threading.Event()
    original = assets._download
    def delayed():
        entered.set();assert gate.wait(3);original()
    monkeypatch.setattr(assets, '_download', delayed)
    monkeypatch.setattr('pdf2zh_next.desktop.assets.subprocess.Popen', lambda *a, **kw: (_ for _ in ()).throw(AssertionError('cancelled work spawned')))
    assets.prepare();assert entered.wait(2);assets.close();gate.set()
    end=time.monotonic()+3
    while assets.busy and time.monotonic()<end:time.sleep(.01)
    assert not assets.busy and assets.child is None
    assert assets.status()['phase']=='cancelled' and assets.status()['state']=='missing'


def test_long_upload_and_collision_preserve_existing_pdf(tmp_path, monkeypatch):
    monkeypatch.setattr(Assets, 'verify', lambda self: True)
    async def metadata(command):return 0,b'{"page_count":2,"page_index":1}\nPNG',b''
    monkeypatch.setattr(server, 'capture_process', metadata)
    app=server.create_app(tmp_path, 't'*64, 54321, tmp_path/'downloads')
    monkeypatch.setattr(server.uuid,'uuid4',lambda:type('Fixed',(),{'hex':'a'*32})())
    headers={'Authorization':'Bearer '+'t'*64}
    with TestClient(app,base_url='http://127.0.0.1:54321',headers=headers) as client:
        first=client.post('/api/files',files={'file':('same.pdf',b'%PDF-first','application/pdf')})
        assert first.status_code==200
        path=tmp_path/'work/uploads'/first.json()['file_id'];before=hashlib.sha256(path.read_bytes()).hexdigest()
        collision=client.post('/api/files',files={'file':('same.pdf',b'%PDF-second','application/pdf')})
        assert collision.status_code==409 and hashlib.sha256(path.read_bytes()).hexdigest()==before
        long=client.post('/api/files',files={'file':('论'*190+'.pdf',b'%PDF-long','application/pdf')})
        assert long.status_code==200 and long.json()['file_id'].endswith('.pdf')
        assert client.get('/api/files/'+long.json()['file_id']+'/preview').status_code==200


def test_http_disconnect_kills_renderer_and_unblocks_next_page(tmp_path, monkeypatch):
    import uvicorn
    monkeypatch.setattr(Assets, 'verify', lambda self: True)
    listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(128);port=listener.getsockname()[1]
    app=server.create_app(tmp_path,'t'*64,port,tmp_path/'downloads')
    file=tmp_path/'work/uploads/12345678__source.pdf';file.write_bytes(b'%PDF-fixture')
    started=threading.Event();children=[]
    def spawn(*args,**kwargs):
        child=subprocess.Popen(*args,**kwargs);children.append(child);started.set();return child
    async def renderer(command):
        page=command[command.index('--page')+1]
        script='import time;time.sleep(30)' if page=='1' else 'print(\'{"page_count":2,"page_index":2}\\nPNG\')'
        return await capture_process([sys.executable,'-c',script],spawn=spawn)
    monkeypatch.setattr(server,'capture_process',renderer)
    control=uvicorn.Server(uvicorn.Config(app,host='127.0.0.1',port=port,log_level='error',access_log=False))
    thread=threading.Thread(target=lambda:control.run(sockets=[listener]),daemon=True);thread.start()
    conn=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
    obsolete=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
    headers={'Authorization':'Bearer '+'t'*64}
    try:
        deadline=time.monotonic()+5
        while not control.started and time.monotonic()<deadline:time.sleep(.01)
        conn.request('GET','/api/files/12345678__source.pdf/preview?page=1',headers=headers)
        assert started.wait(5)
        obsolete.request('GET','/api/files/12345678__source.pdf/preview?page=99',headers=headers)
        time.sleep(.1);obsolete.close();time.sleep(.1)
        # A second request waits on the same semaphore before the first socket
        # closes, so it proves actual queue release rather than cached output.
        result=[]
        def next_page():
            c=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
            try:c.request('GET','/api/files/12345678__source.pdf/preview?page=2',headers=headers);r=c.getresponse();result.append((r.status,r.read()))
            finally:c.close()
        pending=threading.Thread(target=next_page);pending.start();time.sleep(.1);conn.close()
        pending.join(5)
        assert result==[(200,b'PNG\r\n')] or result==[(200,b'PNG\n')]
        assert children[0].poll() is not None and len(children)==2
    finally:
        conn.close();obsolete.close();control.should_exit=True;thread.join(8);listener.close()
        for child in children:
            if child.poll() is None:child.kill();child.wait(3)
        assert not thread.is_alive()
