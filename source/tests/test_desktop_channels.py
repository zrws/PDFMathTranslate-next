import asyncio
import copy
import json
import os
import time
import uuid
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from pdf2zh_next.desktop import channels,server,settings_transaction
from pdf2zh_next.desktop.assets import Assets
from pdf2zh_next.desktop.exports import Exports
from pdf2zh_next.desktop.storage import Store,file_identity,fingerprint


@pytest.fixture
def api(tmp_path,monkeypatch):
    from pdf2zh_next.config.main import ConfigManager
    monkeypatch.setattr(ConfigManager,'_instance',None)
    monkeypatch.setattr(Assets,'verify',lambda self:None)
    monkeypatch.setattr(Assets,'status',lambda self:{'state':'ready','message':'owned fixture','total_bytes':0,'completed_bytes':0})
    async def render(command):return 0,b'{"page_count":7,"page_index":1}\nPNG',b''
    monkeypatch.setattr(server,'capture_process',render)
    app=server.create_app(tmp_path/'home','q'*64,54321,tmp_path/'downloads')
    captured=[]
    monkeypatch.setattr(app.state.engine,'submit',lambda ident,settings,policy:captured.append((ident,settings,policy)))
    with TestClient(app,base_url='http://127.0.0.1:54321',headers={'Authorization':'Bearer '+'q'*64}) as client:
        yield client,app,tmp_path,captured


def profile(client,name='渠道A',key='owned-channel-key-A'):
    response=client.post('/api/channels',json={'name':name,'service':'OpenAI','base_url':'http://127.0.0.1:9876/v1','model':'owned-test-model','api_key':key})
    assert response.status_code==200,response.text
    return next(p for p in response.json()['profiles'] if p['id']==response.json()['active_id'])


def upload(client,root,name='文章.pdf'):
    source=root/name;source.write_bytes(b'%PDF-owned-input')
    response=client.post('/api/files',data={'source_path':str(source)},files={'file':(name,source.read_bytes(),'application/pdf')})
    assert response.status_code==200,response.text
    return source,response.json()


def test_channel_keys_roundtrip_without_plaintext_in_native_home(api):
    client,app,root,_=api
    a=profile(client);b=profile(client,'渠道B','owned-channel-key-B')
    assert client.post('/api/channels/'+a['id']+'/activate',json={}).status_code==200
    assert client.get('/api/settings').json()['active_channel_name']=='渠道A'
    assert client.get('/api/channels').json()['profiles'][-1]['name']=='渠道B'
    for path in (root/'home').rglob('*'):
        if path.is_file():
            raw=path.read_bytes()
            assert b'owned-channel-key-A' not in raw and b'owned-channel-key-B' not in raw,str(path)
    payload=json.dumps([client.get('/api/settings').json(),client.get('/api/channels').json(),client.get('/api/prefs').json(),list(app.state.store.events)])
    assert 'owned-channel-key' not in payload
    restored=Store(root/'home',root/'downloads');vault=channels.Channels(restored)
    assert vault.key(vault.get(a['id']))=='owned-channel-key-A'
    assert vault.key(vault.get(b['id']))=='owned-channel-key-B'


def test_redacted_config_initialization_injects_only_memory(api,monkeypatch):
    client,app,root,_=api
    a=profile(client)
    from pdf2zh_next.config.main import ConfigManager
    import sys
    monkeypatch.setattr(ConfigManager,'_instance',None)
    monkeypatch.setattr(sys,'argv',['pdf2zh','--config-file',str(root/'home/.config/pdf2zh/config.v3.toml'),'--gui'])
    manager=ConfigManager();manager.initialize_config(credential_resolver=channels.Channels(app.state.store).inject)
    assert manager.config_cli_settings.openai_detail.openai_api_key=='owned-channel-key-A'
    assert b'owned-channel-key-A' not in (root/'home/.config/pdf2zh/config.v3.toml').read_bytes()


def test_failure_rolls_back_channel_config_and_prefs_without_plaintext(api,monkeypatch):
    client,app,root,_=api
    a=profile(client);before=app.state.store.path.read_bytes();config=root/'home/.config/pdf2zh/config.v3.toml';before_config=config.read_bytes()
    monkeypatch.setattr(app.state.store,'_persist',lambda:(_ for _ in ()).throw(OSError('owned disk-full fixture')))
    response=client.post('/api/channels',json={**a,'model':'new-model','api_key':'owned-new-failed-secret'})
    assert response.status_code==507
    assert config.read_bytes()==before_config and app.state.store.path.read_bytes()==before
    assert client.get('/api/channels').json()['profiles'][-1]['model']=='owned-test-model'
    assert not any(b'owned-new-failed-secret' in p.read_bytes() for p in (root/'home').rglob('*') if p.is_file())


def test_batch_explicit_channel_survives_active_channel_switch(api):
    client,app,root,captured=api
    a=profile(client);_,file1=upload(client,root,'第一篇.pdf');_,file2=upload(client,root,'第二篇.pdf')
    options={'channel_id':a['id'],'channel_revision':a['revision'],'pages':'','no_dual':False,'no_mono':True}
    first=client.post('/api/tasks',json={**options,'file_id':file1['file_id']},headers={'Idempotency-Key':'batch-item-1'})
    assert first.status_code==200,first.text
    b=profile(client,'渠道B','owned-key-B')
    second=client.post('/api/tasks',json={**options,'file_id':file2['file_id']},headers={'Idempotency-Key':'batch-item-2'})
    assert second.status_code==200,second.text
    assert all(row['options']['channel_id']==a['id'] for row in (first.json(),second.json()))
    assert all(settings['translate_engine_settings']['openai_api_key']=='owned-channel-key-A' for _,settings,_ in captured)
    assert all(settings['pdf']['pages'] is None and settings['pdf']['no_mono'] for _,settings,_ in captured)
    assert client.get('/api/settings').json()['active_channel_id']==b['id']


def test_changed_channel_revision_blocks_remaining_batch_item(api):
    client,_,root,captured=api
    a=profile(client);_,file=upload(client,root)
    assert client.post('/api/channels',json={**a,'model':'changed-model'}).status_code==200
    response=client.post('/api/tasks',json={'file_id':file['file_id'],'channel_id':a['id'],'channel_revision':a['revision']},headers={'Idempotency-Key':'not-received'})
    assert response.status_code==409 and not captured


def test_source_metadata_requires_matching_real_file(api):
    client,_,root,_=api
    source=root/'source.pdf';source.write_bytes(b'%PDF-different')
    response=client.post('/api/files',data={'source_path':str(source)},files={'file':('upload.pdf',b'%PDF-upload','application/pdf')})
    assert response.status_code==409


@pytest.mark.parametrize('old_marker',[False,True])
def test_legacy_migration_protects_native_backup_and_preserves_original(tmp_path,monkeypatch,old_marker):
    from pdf2zh_next.desktop.runtime import migrate_config
    from pdf2zh_next.desktop.protected_config import restore
    from pdf2zh_next.config.main import ConfigManager
    old=tmp_path/'old';source=old/'home/.config/pdf2zh/config.v3.toml';source.parent.mkdir(parents=True)
    raw=b'openai = true\n[openai_detail]\nopenai_api_key = "owned-migration-secret"\nopenai_model = "owned-model"\nopenai_base_url = "http://127.0.0.1:9876/v1"\n'
    source.write_bytes(raw);home=tmp_path/'native'
    if old_marker:migrate_config(home,old)
    migrate_config(home,old,protect_backup=True)
    assert source.read_bytes()==raw
    marker=json.loads((home/'config/migration-v1.json').read_text(encoding='utf-8'));backup=Path(marker['config'][0]['backup'])
    assert restore(backup)==raw
    monkeypatch.setattr(ConfigManager,'_instance',None);monkeypatch.setattr(Assets,'verify',lambda self:None)
    app=server.create_app(home,'m'*64,54321,tmp_path/'downloads')
    with TestClient(app,base_url='http://127.0.0.1:54321',headers={'Authorization':'Bearer '+'m'*64}) as client:
        assert client.get('/api/settings').json()['api_key_set']
    for path in home.rglob('*'):
        if path.is_file():assert b'owned-migration-secret' not in path.read_bytes(),str(path)
    monkeypatch.setattr(ConfigManager,'_instance',None)
    restored=server.create_app(home,'m'*64,54321,tmp_path/'downloads')
    with TestClient(restored,base_url='http://127.0.0.1:54321',headers={'Authorization':'Bearer '+'m'*64}) as client:
        assert client.get('/api/settings').json()['api_key_set']
    assert source.read_bytes()==raw and restore(backup)==raw


def complete(store,root):
    source=root/'source.pdf';source.write_bytes(b'%PDF-original')
    task,_=store.create('create','hash',{'filename':'文章.pdf','path':str(source),'sha256':'source','page_count':7},{'lang_in':'en','lang_out':'zh-CN','no_dual':False,'no_mono':False})
    store.start(task['id']);outputs={}
    for kind in ('dual','mono'):
        path=root/(kind+'.pdf');path.write_bytes(b'%PDF-'+kind.encode());outputs[kind]={'path':str(path),'output_revision':1,**file_identity(path)}
    store.update(task['id'],status='done',outputs=outputs)
    return task['id']


def test_source_export_is_flat_and_saves_only_selected_kind(tmp_path):
    store=Store(tmp_path/'home',tmp_path/'downloads');ident=complete(store,tmp_path);exports=Exports(store)
    key=str(uuid.uuid4());target=tmp_path/'source-dir';target.mkdir();sentinel=target/'文章.pdf';sentinel.write_bytes(b'%PDF-original')
    result=exports.save(ident,target,key,alongside=True,kinds=['dual'])
    assert [Path(p).name for p in result['saved_paths']]==['文章_双语对照.pdf']
    assert all(Path(p).parent==target for p in result['saved_paths'])
    assert exports.save(ident,target,key,alongside=True,kinds=['dual'])['saved_paths']==result['saved_paths']
    assert sentinel.read_bytes()==b'%PDF-original'
    with pytest.raises(ValueError):exports.save(ident,target,key,alongside=True,kinds=['mono'])


@pytest.mark.parametrize('point',['prepared','committed'])
def test_protected_migration_recovers_marker_publication_failure(tmp_path,monkeypatch,point):
    from pdf2zh_next.desktop.runtime import migrate_config
    from pdf2zh_next.desktop import protected_config
    from pdf2zh_next.config.main import ConfigManager
    source=tmp_path/'old/home/.config/pdf2zh/config.v3.toml';source.parent.mkdir(parents=True)
    raw=b'openai=true\n[openai_detail]\nopenai_api_key="owned-crash-migration-key"\nopenai_model="owned-model"\n'
    source.write_bytes(raw);home=tmp_path/'native';original=protected_config.atomic_json
    def fail(path,data):
        if data.get('phase')==point:raise OSError('owned publication failure')
        return original(path,data)
    monkeypatch.setattr(protected_config,'atomic_json',fail)
    with pytest.raises(OSError):migrate_config(home,tmp_path/'old',protect_backup=True)
    target=home/'.config/pdf2zh/config.v3.toml';marker=home/'config/migration-v1.json'
    if point=='prepared':assert not target.exists()
    else:assert target.exists() and json.loads(marker.read_text(encoding='utf-8'))['phase']=='prepared'
    monkeypatch.setattr(protected_config,'atomic_json',original)
    migrate_config(home,tmp_path/'old',protect_backup=True)
    monkeypatch.setattr(ConfigManager,'_instance',None);monkeypatch.setattr(Assets,'verify',lambda self:None)
    app=server.create_app(home,'c'*64,54321,tmp_path/'downloads')
    with TestClient(app,base_url='http://127.0.0.1:54321',headers={'Authorization':'Bearer '+'c'*64}) as client:assert client.get('/api/settings').json()['api_key_set']
    assert source.read_bytes()==raw
    assert not any(b'owned-crash-migration-key' in p.read_bytes() for p in home.rglob('*') if p.is_file())


@pytest.mark.skipif(os.name!='nt',reason='Windows junction ownership boundary')
def test_native_backup_junction_refused_without_touching_outside_owned_sentinel(tmp_path):
    import subprocess
    from pdf2zh_next.desktop.runtime import migrate_config
    home=tmp_path/'native';(home/'config').mkdir(parents=True)
    outside=tmp_path/'outside-owned';outside.mkdir();sentinel=outside/'config.v3.toml';sentinel.write_bytes(b'owned outside sentinel')
    link=home/'config/legacy-backup'
    subprocess.run(['cmd','/c','mklink','/J',str(link),str(outside)],capture_output=True,check=True)
    with pytest.raises(ValueError):migrate_config(home,tmp_path/'old',protect_backup=True)
    assert sentinel.read_bytes()==b'owned outside sentinel' and set(p.name for p in outside.iterdir())=={'config.v3.toml'}


def test_custom_folder_chinese_versions_and_selection(tmp_path):
    store=Store(tmp_path/'home',tmp_path/'downloads');ident=complete(store,tmp_path);exports=Exports(store);target=tmp_path/'other'
    exports.save(ident,target,str(uuid.uuid4()),kinds=['mono'])
    result=exports.save(ident,target,str(uuid.uuid4()),kinds=['mono'])
    assert {Path(p).name for p in result['saved_paths']}=={'文章_译文.pdf','文章_译文_第2版.pdf'}
    assert all(Path(p).parent==target/'文章' for p in result['saved_paths'])


def test_probe_models_errors_and_no_redirect_or_secret_echo(monkeypatch):
    original=httpx.AsyncClient;calls=[]
    async def handle(request):
        calls.append(request)
        if len(calls)==1:return httpx.Response(200,json={'data':[{'id':'model-b'},{'id':'model-a'}]})
        return httpx.Response(302,headers={'Location':'http://unexpected.invalid/secret'},json={'error':'owned-key-sentinel'})
    monkeypatch.setattr(httpx,'AsyncClient',lambda **kwargs:original(transport=httpx.MockTransport(handle),**kwargs))
    row={'service':'OpenAI','base_url':'http://127.0.0.1:9999/v1','model':'model-a'}
    assert asyncio.run(channels.probe(row,'owned-key-sentinel',True))['models']==['model-a','model-b']
    with pytest.raises(ValueError) as error:asyncio.run(channels.probe(row,'owned-key-sentinel'))
    assert 'owned-key-sentinel' not in str(error.value) and len(calls)==2


def test_probe_absolute_timeout_releases_slot(monkeypatch):
    original=httpx.AsyncClient;closed=[]
    class Slow(httpx.AsyncByteStream):
        async def __aiter__(self):
            while True:await asyncio.sleep(.02);yield b' '
        async def aclose(self):closed.append(True)
    async def handle(request):return httpx.Response(200,stream=Slow())
    monkeypatch.setattr(httpx,'AsyncClient',lambda **kwargs:original(transport=httpx.MockTransport(handle),**kwargs))
    monkeypatch.setattr(channels,'PROBE_TIMEOUT_SECONDS',.07)
    start=time.monotonic()
    with pytest.raises(ValueError):asyncio.run(channels.probe({'service':'OpenAI','base_url':'http://127.0.0.1:9999/v1','model':'fixture'},'fixture'))
    assert time.monotonic()-start<1 and closed
    assert channels.PROBE_SLOTS.acquire(blocking=False)
    assert channels.PROBE_SLOTS.acquire(blocking=False)
    channels.PROBE_SLOTS.release();channels.PROBE_SLOTS.release()


def test_probe_cancel_closes_stream_and_releases_both_slots(monkeypatch):
    original=httpx.AsyncClient;closed=[]
    class Waiting(httpx.AsyncByteStream):
        async def __aiter__(self):
            yield b' '
            await asyncio.sleep(60)
        async def aclose(self):closed.append(True)
    async def handle(request):return httpx.Response(200,stream=Waiting())
    monkeypatch.setattr(httpx,'AsyncClient',lambda **kwargs:original(transport=httpx.MockTransport(handle),**kwargs))
    async def scenario():
        task=asyncio.create_task(channels.probe({'service':'OpenAI','base_url':'http://127.0.0.1:9999/v1','model':'fixture'},'fixture'))
        await asyncio.sleep(.03);task.cancel()
        with pytest.raises(asyncio.CancelledError):await task
    asyncio.run(scenario())
    assert closed and channels.PROBE_SLOTS.acquire(blocking=False) and channels.PROBE_SLOTS.acquire(blocking=False)
    channels.PROBE_SLOTS.release();channels.PROBE_SLOTS.release()
