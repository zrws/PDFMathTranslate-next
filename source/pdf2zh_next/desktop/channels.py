"""Named native channels. Secrets never enter public payloads or task snapshots."""
import base64
import asyncio
import copy
import ctypes
from ctypes import wintypes
import json
import os
import re
import threading
import time
import uuid
from urllib.parse import urlparse
from .snapshots import SECRET
from pdf2zh_next.config.translate_engine_model import GUI_PASSWORD_FIELDS, TRANSLATION_ENGINE_METADATA


def secret_values(model,path=()):
    rows=[]
    for name in type(model).model_fields:
        value=getattr(model,name)
        if (name in GUI_PASSWORD_FIELDS or SECRET.search(name)) and isinstance(value,str) and value:rows.append([list(path+(name,)),value])
        elif hasattr(type(value),'model_fields'):rows.extend(secret_values(value,path+(name,)))
    return rows


def without_secrets(model):
    result=model.model_copy(deep=True)
    for path,_ in secret_values(result):
        target=result
        for key in path[:-1]:target=getattr(target,key)
        setattr(target,path[-1],'')
    return result


class Blob(ctypes.Structure):
    _fields_=[('size',wintypes.DWORD),('data',ctypes.POINTER(ctypes.c_ubyte))]


def crypt(value, decrypt=False):
    if os.name!='nt': raise ValueError('本机渠道密钥保护需要 Windows。')
    raw=base64.b64decode(value,validate=True) if decrypt else value.encode('utf-8')
    buffer=ctypes.create_string_buffer(raw)
    source=Blob(len(raw),ctypes.cast(buffer,ctypes.POINTER(ctypes.c_ubyte)));target=Blob()
    library=ctypes.WinDLL('crypt32',use_last_error=True)
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.LocalFree.argtypes=[ctypes.c_void_p];kernel.LocalFree.restype=ctypes.c_void_p
    if decrypt:
        call=library.CryptUnprotectData
        call.argtypes=[ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(Blob)]
        args=(ctypes.byref(source),None,None,None,None,1,ctypes.byref(target))
    else:
        call=library.CryptProtectData
        call.argtypes=[ctypes.POINTER(Blob),wintypes.LPCWSTR,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(Blob)]
        args=(ctypes.byref(source),'PDFMathTranslate channel',None,None,None,1,ctypes.byref(target))
    call.restype=wintypes.BOOL
    if not call(*args):raise ValueError('无法读取或保护渠道密钥，请在本机重新输入密钥。')
    try:
        result=ctypes.string_at(target.data,target.size)
        return result.decode('utf-8') if decrypt else base64.b64encode(result).decode('ascii')
    finally:kernel.LocalFree(ctypes.cast(target.data,ctypes.c_void_p))


def validate_url(value):
    if not isinstance(value,str) or len(value)>2048:raise ValueError('API 地址无效。')
    if not value:return ''
    parsed=urlparse(value)
    try:parsed.port
    except ValueError:raise ValueError('API 地址端口无效。') from None
    if parsed.scheme not in {'http','https'} or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or re.search(r'[\x00-\x20]',value):
        raise ValueError('API 地址需为 HTTP(S) 地址，不能含密钥、空格、查询参数或片段。')
    return value.rstrip('/')


class Channels:
    def __init__(self,store):self.store=store
    def data(self):
        with self.store.lock:return copy.deepcopy(self.store.state.get('channels',{'profiles':[],'active_id':''}))
    @staticmethod
    def public_profile(profile):return {**{k:profile[k] for k in ('id','name','service','base_url','model')},'api_key_set':bool(profile.get('secret')),'revision':profile.get('revision',1)}
    def public(self):
        data=self.data();return {'active_id':data['active_id'],'profiles':[self.public_profile(p) for p in data['profiles']]}
    def get(self,ident):
        result=next((p for p in self.data()['profiles'] if p['id']==ident),None)
        if result is None:raise ValueError('渠道不存在，请重新选择。')
        return result
    @staticmethod
    def key(profile):return crypt(profile['secret'],True) if profile.get('secret') else ''
    def initial(self,current,key,cli=None):
        with self.store.lock:
            if 'channels' in self.store.state:return
            ident=uuid.uuid4().hex
            row={'id':ident,'name':'原有配置','service':current['service'],'base_url':current['base_url'],'model':current['model'],'secret':crypt(key) if key else '','revision':1}
            archive=secret_values(cli) if cli is not None else []
            self.store.state['channels']={'active_id':ident,'profiles':[row],'legacy_secrets':crypt(json.dumps(archive,ensure_ascii=False)) if archive else ''}
            try:self.store._persist()
            except Exception:self.store.state.pop('channels',None);raise
    def draft(self,payload,services):
        data=self.data();ident=payload.get('id') or uuid.uuid4().hex
        old=next((p for p in data['profiles'] if p['id']==ident),None)
        if payload.get('id') and old is None:raise ValueError('渠道不存在，请刷新后重试。')
        if old is None and len(data['profiles'])>=64:raise ValueError('最多保存 64 个渠道，请先删除不用的渠道。')
        name=payload.get('name','')
        if not isinstance(name,str):raise ValueError('渠道名称无效。')
        name=name.strip()
        if not name or len(name)>80 or re.search(r'[\x00-\x1f]',name):raise ValueError('渠道名称需为 1–80 个可见字符。')
        if payload.get('service') not in services:raise ValueError('请选择有效的翻译引擎。')
        if any(p['id']!=ident and p['name'].casefold()==name.casefold() for p in data['profiles']):raise ValueError('该渠道名称已存在，请换一个名称。')
        model=payload.get('model','')
        if not isinstance(model,str) or len(model)>256 or re.search(r'[\x00-\x1f]',model):raise ValueError('模型名称无效。')
        row={'id':ident,'name':name,'service':payload['service'],'model':model.strip(),'base_url':validate_url(payload.get('base_url','')),'secret':old.get('secret','') if old else '','revision':old.get('revision',1)+1 if old else 1}
        if 'api_key' in payload:
            key=payload['api_key']
            if not isinstance(key,str) or len(key)>8192 or '\n' in key or '\r' in key:raise ValueError('API 密钥格式无效。')
            row['secret']=crypt(key) if key else ''
        data['profiles']=[row if p['id']==ident else p for p in data['profiles']]+([] if old else [row])
        data['active_id']=ident
        return data,row

    def inject(self,cli):
        data=self.data()
        if not data['profiles']:
            from .protected_config import inject_bootstrap
            inject_bootstrap(self.store.path.parent.parent,cli)
            return
        if data.get('legacy_secrets'):
            for path,value in json.loads(crypt(data['legacy_secrets'],True)):
                target=cli
                for key in path[:-1]:target=getattr(target,key)
                setattr(target,path[-1],value)
        row=self.get(data['active_id'])
        for meta in TRANSLATION_ENGINE_METADATA:
            setattr(cli,meta.cli_flag_name,meta.translate_engine_type==row['service'])
            if meta.translate_engine_type==row['service'] and meta.cli_detail_field_name:
                detail=getattr(cli,meta.cli_detail_field_name)
                from pdf2zh_next.http_api import _pick_field
                for keyword,value in (('model',row['model']),('base_url',row['base_url']),('api_key',self.key(row))):
                    field=_pick_field(detail,keyword)
                    if field:setattr(detail,field,value)


PROBE_SLOTS=threading.BoundedSemaphore(2)
PROBE_TIMEOUT_SECONDS=15
DEFAULT_URLS={'OpenAI':'https://api.openai.com/v1','DeepSeek':'https://api.deepseek.com/v1','SiliconFlow':'https://api.siliconflow.cn/v1','Groq':'https://api.groq.com/openai/v1','Grok':'https://api.x.ai/v1','Ollama':'http://127.0.0.1:11434/v1'}
OPENAI_SERVICES=set(DEFAULT_URLS)|{'OpenAICompatible','AliyunDashScope','QwenMt'}


async def probe(profile,key,models=False):
    import httpx
    service=profile['service']
    if service not in OPENAI_SERVICES:raise ValueError('该引擎没有 OpenAI 兼容的探测接口；请使用兼容渠道，或手动填写模型。原翻译引擎仍可使用。')
    base=validate_url(profile.get('base_url') or DEFAULT_URLS.get(service,''))
    if not base:raise ValueError('请先填写该渠道的 API 地址。')
    if not models and not profile.get('model'):raise ValueError('请先探测并选择模型，或手动填写模型名称。')
    if not PROBE_SLOTS.acquire(blocking=False):raise ValueError('已有渠道探测正在进行，请稍后重试。')
    started=time.monotonic()
    try:
        headers={'Authorization':'Bearer '+key} if key else {}
        endpoint=base+('/models' if models else '/chat/completions')
        body=None if models else {'model':profile['model'],'messages':[{'role':'user','content':'Please reply only OK.'}],'max_tokens':16,'stream':False}
        try:
            async with asyncio.timeout(PROBE_TIMEOUT_SECONDS):
                async with httpx.AsyncClient(timeout=httpx.Timeout(15,connect=5),follow_redirects=False) as client:
                    async with client.stream('GET' if models else 'POST',endpoint,headers=headers,json=body) as response:
                        if not 200<=response.status_code<300:
                            labels={401:'密钥认证失败',403:'渠道拒绝访问',404:'接口或模型不存在',429:'请求受限，请稍后重试'}
                            raise ValueError(labels.get(response.status_code,'渠道返回错误')+f'（HTTP {response.status_code}）。')
                        chunks=[];size=0
                        async for chunk in response.aiter_bytes():
                            size+=len(chunk)
                            if size>512*1024:raise ValueError('渠道响应超过大小限制，请手动填写模型。')
                            chunks.append(chunk)
                        data=json.loads(b''.join(chunks))
        except (TimeoutError,httpx.TimeoutException):raise ValueError('渠道连接超时，请检查地址、代理或网络。') from None
        except httpx.HTTPError:raise ValueError('无法连接渠道，请检查地址、证书和网络。') from None
        except (json.JSONDecodeError,UnicodeError):raise ValueError('渠道没有返回有效的 API JSON，请核对地址。') from None
        if models:
            if not isinstance(data,dict) or not isinstance(data.get('data'),list):raise ValueError('该地址没有返回兼容的模型列表，请手动填写模型。')
            ids=sorted({p['id'] for p in data['data'] if isinstance(p,dict) and isinstance(p.get('id'),str) and 0<len(p['id'])<=256})[:500]
            if not ids:raise ValueError('渠道没有提供可用模型，请手动填写模型或检查权限。')
            return {'models':ids,'message':f'已发现 {len(ids)} 个模型。','latency_ms':round((time.monotonic()-started)*1000)}
        choices=data.get('choices') if isinstance(data,dict) else None
        message=choices[0].get('message') if isinstance(choices,list) and choices and isinstance(choices[0],dict) else None
        if not isinstance(message,dict) or not isinstance(message.get('content'),str) or not message['content'].strip():
            raise ValueError('渠道未返回有效文本，未将其判为模型测试成功。')
        return {'message':'渠道与所选模型测试成功。','latency_ms':round((time.monotonic()-started)*1000)}
    finally:PROBE_SLOTS.release()
