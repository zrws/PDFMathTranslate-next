"""Authenticated native control API. Startup never warms translation models."""
from __future__ import annotations
import asyncio
import collections
import contextlib
import hmac
from email.header import decode_header, make_header
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response, StreamingResponse
from fastapi.exceptions import RequestValidationError
from .assets import Assets
from .engine import Engine
from .exports import Exports, directory
from .policy import effective_policy, apply_engine_budget
from .runtime import DataOwner, migrate_config, migrate_history
from .storage import Store, atomic_json, file_identity, fingerprint
from .snapshots import freeze, restore
from . import settings_transaction
from .channels import Channels, without_secrets, probe as probe_channel
from .preview_control import capture_process, while_connected, PreviewDisconnected


def create_app(home, token, port, downloads, *, legacy_root=None):
    home = Path(home).resolve()
    work = home/"work"
    work.mkdir(parents=True, exist_ok=True)
    upload_dir = work/"uploads"; upload_dir.mkdir(exist_ok=True)
    settings_transaction.recover(home)
    os.environ["PDF2ZH_CONFIG_FILE"] = str(home/".config/pdf2zh/config.v3.toml")
    sys.argv = ["pdf2zh", "--config-file", os.environ["PDF2ZH_CONFIG_FILE"], "--gui"]
    from pdf2zh_next import http_api as legacy
    from pdf2zh_next.config.translate_engine_model import TRANSLATION_ENGINE_METADATA
    store = Store(home, downloads)
    if legacy_root: migrate_history(home, legacy_root, store)
    assets = Assets(home, store)
    engine = Engine(home, store)
    exports = Exports(store)
    channels = Channels(store)
    manager=legacy.ConfigManager()
    if manager._settings is None:manager.initialize_config(credential_resolver=channels.inject)
    initial=legacy.settings_payload()
    _,initial_detail=legacy._current_engine(legacy._cli_settings())
    initial_key_field=legacy._pick_field(initial_detail,'api_key')
    channels.initial(initial,getattr(initial_detail,initial_key_field,'') if initial_key_field else '',legacy._cli_settings())
    manager.write_user_default_config_file(without_secrets(legacy._cli_settings()))
    @contextlib.asynccontextmanager
    async def lifespan(app):
        yield
        assets.close()
        await asyncio.to_thread(engine.close)
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None,lifespan=lifespan)
    app.state.store = store; app.state.assets = assets; app.state.engine = engine
    tickets = {}
    tickets_lock = threading.Lock()
    render_lock = asyncio.Semaphore(1)
    preview_cache = collections.OrderedDict()
    expected_host = f"127.0.0.1:{port}"
    settings_lock = threading.RLock()

    def authentication_error(request):
        if request.headers.get("host", "") != expected_host or request.headers.get("origin") not in (None, "http://"+expected_host):
            return JSONResponse({"detail": "请求来源不受许可。"}, status_code=403)
        auth = request.headers.get("authorization", "")
        valid = len(auth)<4096 and hmac.compare_digest(auth.encode(), ("Bearer "+token).encode())
        if not valid and request.url.path == "/api/events":
            ticket = request.query_params.get("ticket", "")
            with tickets_lock:
                expiry = tickets.pop(ticket, 0)
                valid = bool(expiry and expiry >= time.monotonic())
        if not valid: return JSONResponse({"detail": "本次应用会话已失效，请重新启动服务。"}, status_code=401)
        return None

    class SessionAuthentication:
        # Pure ASGI preserves the original receive channel, including the
        # http.disconnect message used to cancel preview subprocesses.
        def __init__(self, app):self.app=app
        async def __call__(self, scope, receive, send):
            if scope['type']=='http':
                error=authentication_error(Request(scope))
                if error is not None:
                    await error(scope,receive,send)
                    return
            await self.app(scope,receive,send)
    app.add_middleware(SessionAuthentication)

    @app.exception_handler(ValueError)
    async def value_error(request, exc):
        return JSONResponse({"detail": str(exc)}, status_code=409)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return JSONResponse({"detail": "请求参数无效，请核对必填项与取值。"}, status_code=422)

    @app.exception_handler(OSError)
    async def io_error(request, exc):
        return JSONResponse({"detail": "无法访问或写入文件，请检查目录权限、磁盘空间和文件占用。"}, status_code=507)

    @app.exception_handler(Exception)
    async def unexpected(request, exc):
        return JSONResponse({"detail": "服务未完成操作，请检查配置、资源与磁盘后重试。"}, status_code=500)

    @app.get("/api/health")
    def health():
        return {"api_version": "1.0", "instance_id": store.instance_id, "app_version": "2.9.0", "control_ready": True, "warmup": assets.status(), "data_dirs": {"home": str(home), "config": str(home/".config/pdf2zh"), "work": str(work), "cache": str(home/".cache"), "logs": str(home/"logs")}}

    def settings_unlocked():
        value = legacy.settings_payload()
        prefs = store.prefs()
        value.update(resource_tier=prefs["resource_tier"], requested_qps=prefs["requested_qps"], effective_policy=effective_policy(prefs["resource_tier"], prefs["requested_qps"]))
        value.pop("api_key_masked", None)
        value["auto_update"]=prefs.get("auto_update",True)
        channel_data=channels.public()
        value['active_channel_id']=channel_data['active_id']
        value['active_channel_name']=next((p['name'] for p in channel_data['profiles'] if p['id']==channel_data['active_id']),'未选择渠道')
        value['active_channel_revision']=next((p['revision'] for p in channel_data['profiles'] if p['id']==channel_data['active_id']),1)
        return value

    def settings():
        with settings_lock: return settings_unlocked()

    @app.get("/api/settings")
    def get_settings(): return settings()

    @app.put("/api/settings")
    def put_settings(payload: dict):
        with settings_lock: return put_settings_unlocked(payload)

    def put_settings_unlocked(payload):
        current = store.prefs()
        tier = payload.get("resource_tier", current["resource_tier"])
        qps = payload.get("qps", current["requested_qps"])
        if not isinstance(qps, int) or isinstance(qps, bool) or not 1<=qps<=1000: raise HTTPException(400, "QPS 需为 1–1000 的整数。")
        effective_policy(tier, qps)
        changes={"resource_tier":tier,"requested_qps":qps}
        if 'save_mode' in payload:
            if payload['save_mode'] not in {'custom','source'}:raise HTTPException(400,'请选择有效的保存方式。')
            changes['save_mode']=payload['save_mode']
        if "auto_update" in payload:
            if not isinstance(payload["auto_update"],bool):raise HTTPException(400,"自动更新偏好需为开关值。")
            changes["auto_update"]=payload["auto_update"]
        if "download_dir" in payload:
            folder=directory(payload["download_dir"])
            if folder.exists() and not folder.is_dir():raise HTTPException(400,"保存位置必须是文件夹。")
            changes["download_dir"]=str(folder)
        if payload.get("base_url"):
            parsed = urlparse(payload["base_url"])
            if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
                raise HTTPException(400, "API 地址需为有效 HTTP(S) 地址，不能在地址中保存密钥。")
        fields={k:v for k,v in payload.items() if k in legacy.SettingsUpdate.model_fields}
        channel_data=None
        if 'channel' in payload:
            if not isinstance(payload['channel'],dict):raise HTTPException(400,'渠道配置无效。')
            channel_data,row=channels.draft(payload['channel'],legacy.settings_payload()['services'])
            fields.update(service=row['service'],model=row['model'],base_url=row['base_url'],api_key=channels.key(row))
        elif any(k in payload for k in ('service','model','base_url','api_key')):
            data=channels.data();old=channels.get(data['active_id']);current_settings=legacy.settings_payload()
            draft={k:old[k] for k in ('id','name')}
            draft.update({k:payload.get(k,current_settings[k]) or '' for k in ('service','model','base_url')})
            if not draft['service']:draft['service']=current_settings['service']
            if 'api_key' in payload:draft['api_key']=payload['api_key'] or ''
            channel_data,_=channels.draft(draft,current_settings['services'])
        update=legacy.SettingsUpdate.model_validate(fields)
        commit_settings(update,changes,channel_data)
        return settings()

    def commit_settings(update,changes,channel_data=None):
        manager=legacy._config_manager();before_cli=manager.config_cli_settings.clone();before_model=manager._settings
        def rollback_memory():
            manager.config_cli_settings=before_cli;manager._settings=before_model
        settings_transaction.commit(home,store,lambda: legacy.apply_settings(update,persist_secrets=False) if update is not None else None,rollback_memory,changes,channel_data)

    def activate_channel(data,row):
        update=legacy.SettingsUpdate(service=row['service'],model=row['model'],base_url=row['base_url'],api_key=channels.key(row))
        data['active_id']=row['id'];commit_settings(update,{},data)
        return channels.public()

    @app.get('/api/channels')
    def list_channels():
        with settings_lock:return channels.public()

    @app.post('/api/channels')
    def save_channel(payload:dict):
        with settings_lock:
            data,row=channels.draft(payload,legacy.settings_payload()['services'])
            return activate_channel(data,row)

    @app.post('/api/channels/{ident}/activate')
    def use_channel(ident:str):
        with settings_lock:return activate_channel(channels.data(),channels.get(ident))

    @app.delete('/api/channels/{ident}')
    def delete_channel(ident:str):
        with settings_lock:
            data=channels.data();channels.get(ident)
            if ident==data['active_id']:raise HTTPException(400,'请先使用另一个渠道，再删除当前渠道。')
            if any(t['status'] not in {'done','failed','cancelled'} and t['options'].get('channel_id')==ident for t in store.state['tasks'].values()):raise HTTPException(409,'仍有任务引用该渠道，请等待任务结束。')
            data['profiles']=[p for p in data['profiles'] if p['id']!=ident]
            commit_settings(None,{},data);return channels.public()

    @app.post('/api/channels/probe')
    async def test_channel(request:Request,payload:dict):
        with settings_lock:
            draft={**payload,'name':payload.get('name') or '临时测试'}
            _,row=channels.draft(draft,legacy.settings_payload()['services'])
            secret=channels.key(row)
        try:return await while_connected(probe_channel(row,secret,payload.get('action')=='models'),request.is_disconnected)
        except PreviewDisconnected:raise HTTPException(499,'渠道探测已取消。')

    @app.get("/api/capabilities")
    def capabilities():
        return {"services": settings()["services"], "outputs": ["dual", "mono", "glossary"], "effective_policy": settings()["effective_policy"], "preview_max_width": 1600, "preview_max_height": 2400, "preview_cache_bytes": 32*1024*1024}

    @app.get("/api/prefs")
    def prefs(): return store.prefs()

    @app.put("/api/prefs")
    def put_prefs(payload: dict):
        with settings_lock:
            target = directory(payload.get("download_dir", ""))
            if target.exists() and not target.is_dir(): raise HTTPException(400, "保存位置必须是文件夹。")
            mode=payload.get('save_mode',store.prefs().get('save_mode','custom'))
            if mode not in {'custom','source'}:raise HTTPException(400,'请选择有效的保存方式。')
            return store.prefs({"download_dir": str(target),'save_mode':mode})

    @app.get("/api/assets/status")
    def asset_status(): return assets.status()

    @app.post("/api/assets/prepare")
    def prepare(): return assets.prepare()

    @app.post("/api/assets/cancel")
    def cancel_assets():assets.close();return assets.status()

    @app.post("/api/auth/ticket")
    def ticket():
        with tickets_lock:
            now = time.monotonic()
            for key in list(tickets):
                if tickets[key]<now: tickets.pop(key)
            if len(tickets)>=32: raise HTTPException(429, "连接请求过多，请稍后重试。")
            ticket = secrets.token_urlsafe(24); tickets[ticket] = now+10
        return {"ticket": ticket, "expires_in": 10}

    @app.get("/api/events")
    async def events(request: Request, last_event_id: str | None = Header(default=None)):
        cursor = None
        if last_event_id:
            try:
                instance, number = last_event_id.rsplit(":", 1)
                cursor = (instance, int(number))
            except ValueError: raise HTTPException(400, "进度游标无效，请重新连接。")
        async def stream():
            nonlocal cursor
            while not await request.is_disconnected():
                rows = store.read_events(cursor)
                for event in rows:
                    if event["type"] == "snapshot": event["data"]["assets"] = assets.status()
                    wire_id = f'{event["instance_id"]}:{event["event_id"]}'
                    yield f'id: {wire_id}\nevent: {event["type"]}\ndata: {json.dumps(event, ensure_ascii=False, separators=(",", ":"))}\n\n'
                    cursor = (event["instance_id"], event["event_id"])
                    if event["type"] == "resync": return
                if not rows:
                    await asyncio.to_thread(store.wait, cursor[1])
                    yield ": keepalive\n\n"
        return StreamingResponse(stream(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

    async def render(path, page, width, request=None):
        try:return await while_connected(render_locked(path,page,width),request.is_disconnected if request else None)
        except PreviewDisconnected:raise HTTPException(499,"预览请求已取消。")

    async def render_locked(path, page, width):
        key = (str(path), path.stat().st_mtime_ns, path.stat().st_size, page, width)
        async with render_lock:
            if key in preview_cache:
                preview_cache.move_to_end(key)
                return preview_cache[key]
            try:
                code, output, error = await capture_process([sys.executable, "-m", "pdf2zh_next.desktop.preview", str(path), "--page", str(page), "--width", str(width)])
                if code: raise HTTPException(400, "无法读取 PDF，请确认文件未损坏且未加密。")
                header, png = output.split(b"\n", 1)
                result = (json.loads(header), png)
                if width:
                    preview_cache[key] = result
                    while preview_cache and (len(preview_cache)>8 or sum(len(v[1]) for v in preview_cache.values())>32*1024*1024): preview_cache.popitem(last=False)
                return result
            except TimeoutError: raise HTTPException(504, "预览读取超时，请更换页面或继续翻译。")

    def upload_path(file_id):
        if not re.fullmatch(r"[0-9a-f]{8}__[^\\/\x00]+\.pdf", file_id, re.I): raise HTTPException(404, "文件不存在，请重新导入。")
        path = (upload_dir/file_id).resolve()
        if path.parent != upload_dir.resolve() or not path.is_file(): raise HTTPException(404, "文件不存在，请重新导入。")
        return path

    @app.post("/api/files")
    async def upload(request: Request, file: UploadFile = File(...),source_path:str=Form('')):
        raw_filename=file.filename or "文档.pdf"
        # .NET MultipartFormDataContent emits MIME encoded words for Unicode
        # filename; python-multipart leaves that fallback undecoded.
        try: raw_filename=str(make_header(decode_header(raw_filename)))
        except (ValueError,LookupError,UnicodeError): raise HTTPException(400,"文件名编码无效，请重命名后导入。")
        filename = re.sub(r'[<>:"|?*\x00-\x1f]', "_", Path(raw_filename.replace("\\", "/")).name)
        if not filename.lower().endswith(".pdf"): raise HTTPException(400, "仅支持 PDF 文件。")
        file_id = uuid.uuid4().hex[:8]+"__"+filename[:-4][:176]+".pdf"
        path = upload_dir/file_id
        size = 0
        created = False
        try:
            with path.open("xb") as out:
                created = True
                while chunk := await file.read(1024*1024):
                    size += len(chunk)
                    if size>100*1024*1024: raise HTTPException(413, "PDF 超过 100 MB，请拆分后导入。")
                    if size == len(chunk) and b"%PDF-" not in chunk[:1024]: raise HTTPException(400, "文件不是有效的 PDF。")
                    out.write(chunk)
            metadata, _ = await render(path, 1, 0, request)
            row = {"file_id": file_id, "filename": filename, "path": str(path), "page_count": metadata["page_count"], **file_identity(path)}
            if source_path:
                if len(source_path)>32767 or not Path(source_path).is_absolute():raise HTTPException(400,'源文件路径无效，请重新选择本地 PDF。')
                original=Path(source_path).resolve()
                if not original.is_file() or file_identity(original)!={k:row[k] for k in ('size_bytes','sha256')}:raise HTTPException(409,'源文件已改变，请重新导入后再保存到源目录。')
                row['source_directory']=str(original.parent)
            atomic_json(path.with_suffix(".meta.json"), row)
            return {k:v for k,v in row.items() if k != "path"}
        except FileExistsError:
            raise HTTPException(409,"文件标识冲突，请重新导入；已有文件已保留。") from None
        except BaseException:
            if created:path.unlink(missing_ok=True)
            raise

    def png_response(result):
        meta, png = result
        return Response(png, media_type="image/png", headers={"X-Page-Count": str(meta["page_count"]), "X-Page-Index": str(meta["page_index"]), "Cache-Control": "private, max-age=30"})

    @app.get("/api/files/{file_id}/preview")
    async def file_preview(file_id: str, request: Request, page: int = 1, width: int = 1200): return png_response(await render(upload_path(file_id), max(1, page), max(200, min(1600, width)), request))

    def require_task(ident):
        task = store.get(ident)
        if not task: raise HTTPException(404, "任务不存在。")
        return task

    def output_path(ident, kind):
        task = require_task(ident)
        output = task["outputs"].get(kind)
        if not output: raise HTTPException(404, "该输出尚未生成。")
        path = Path(output["path"]).resolve()
        if not path.is_relative_to((work/"outputs").resolve()) or not path.is_file(): raise HTTPException(404, "产物已移动或不可用，请重试翻译。")
        return path

    @app.get("/api/tasks/{ident}/preview")
    async def task_preview(ident: str, request: Request, kind: str = "dual", page: int = 1, width: int = 1200): return png_response(await render(output_path(ident, kind), max(1, page), max(200, min(1600, width)), request))

    @app.get("/api/tasks/{ident}/source-preview")
    async def source_preview(ident: str, request: Request, page: int = 1, width: int = 1200):
        path=Path(require_task(ident)["file_path"]).resolve()
        if path.parent!=upload_dir.resolve() or not path.is_file():raise HTTPException(404,"原文不可用，请重新导入。")
        return png_response(await render(path,max(1,page),max(200,min(1600,width)),request))

    @app.get("/api/tasks/{ident}/download")
    def download(ident: str, kind: str = "dual"): return FileResponse(output_path(ident, kind))

    def build_settings(options):
        cli = legacy._cli_settings().clone()
        chosen = options["engine"]
        for meta in TRANSLATION_ENGINE_METADATA: setattr(cli, meta.cli_flag_name, meta.translate_engine_type == chosen["service"])
        if "term_credential_provider" in options:
            for meta in TRANSLATION_ENGINE_METADATA:
                flag="term_"+meta.cli_flag_name
                if hasattr(cli,flag):setattr(cli,flag,meta.translate_engine_type==options["term_credential_provider"])
        service, detail = legacy._current_engine(cli)
        for keyword in ("base_url", "model"):
            field = legacy._pick_field(detail, keyword)
            if field: setattr(detail, field, chosen[keyword])
        if options.get('channel_id'):
            profile=channels.get(options['channel_id'])
            if profile['service']!=chosen['service']:raise ValueError('原渠道的引擎类型已改变，请重新导入或恢复该渠道后重试。')
            field=legacy._pick_field(detail,'api_key')
            if field:setattr(detail,field,channels.key(profile))
        cli.translation.lang_in = options["lang_in"]; cli.translation.lang_out = options["lang_out"]
        cli.pdf.pages = options["pages"] or None; cli.pdf.no_dual = options["no_dual"]; cli.pdf.no_mono = options["no_mono"]
        cli.translation.no_auto_extract_glossary = not options["auto_term_extraction"]
        if options.get("watermark_output_mode"): cli.pdf.watermark_output_mode=options["watermark_output_mode"]
        result = cli.to_settings_model(); result.basic.input_files = set()
        if "settings_snapshot" in options: result=restore(options,result)
        return result

    def request_fingerprint(payload, file_sha, parent):
        values={k:payload[k] for k in ("lang_in","lang_out","pages","no_dual","no_mono","auto_term_extraction","watermark_output_mode","export_dir","save_mode","channel_id","channel_revision") if k in payload}
        for key in ("lang_in","lang_out"):
            if key in values: values[key]=legacy._normalize_lang(values[key])
        if "pages" in values: values["pages"]=re.sub(r"\s+","",values["pages"] or "")
        return fingerprint({"file_sha256":file_sha,"values":values,"parent_task_id":parent})

    def submit(payload, key, parent=None, original=None):
        with settings_lock:return submit_locked(payload,key,parent,original)

    def submit_locked(payload, key, parent=None, original=None):
        if not key or len(key)>128: raise HTTPException(400, "提交需要有效的请求标识。")
        old=store.lookup(key,parent)
        if old:
            response=store.get(old["task_id"]) or old["response"]
            sha=response["file_sha256"]
            if not parent and payload.get("file_id")!=Path(response["file_path"]).name:
                other=upload_path(payload.get("file_id",""));sha=json.loads(other.with_suffix(".meta.json").read_text(encoding="utf-8"))["sha256"]
            raw_hash=request_fingerprint(payload,sha,parent)
            if raw_hash!=old.get("request_hash"):raise HTTPException(409,"同一请求标识的内容已改变，请确认任务后重新提交。")
            return store.public(response)
        if assets.status()["state"] != "ready": raise HTTPException(409, "排版资源尚未就绪，请先在「资源与设置」中完成准备。")
        if original:
            file = {"filename": original["filename"], "path": original["file_path"], "sha256": original["file_sha256"], "page_count": original["page_count"]}
            if not Path(file["path"]).is_file(): raise HTTPException(409, "原文件不可用，请重新导入 PDF。")
            options = original["options"]
        else:
            path = upload_path(payload.get("file_id", ""))
            file = json.loads(path.with_suffix(".meta.json").read_text(encoding="utf-8"))
            current = settings()
            selected=channels.get(payload.get('channel_id') or current['active_channel_id'])
            if 'channel_revision' in payload and payload['channel_revision']!=selected.get('revision',1):raise HTTPException(409,'渠道配置已改变，其余文件仍保留；请核对后重新提交。')
            current.update({k:selected[k] for k in ('service','model','base_url')})
            for flag in ('no_dual','no_mono','auto_term_extraction'):
                if flag in payload and not isinstance(payload[flag],bool):raise HTTPException(400,'输出与术语选项需为开关值。')
            if not isinstance(payload.get('pages',''),str):raise HTTPException(400,'页码范围需为文本，留空表示全部页面。')
            options = {"lang_in": legacy._normalize_lang(payload.get("lang_in")) or current["lang_in"], "lang_out": legacy._normalize_lang(payload.get("lang_out")) or current["lang_out"], "pages": payload.get("pages", ""), "no_dual": payload.get("no_dual", current["no_dual"]), "no_mono": payload.get("no_mono", current["no_mono"]), "auto_term_extraction": payload.get("auto_term_extraction", current["auto_term_extraction"]), "watermark_output_mode":payload.get("watermark_output_mode",current["watermark_output_mode"]), "export_dir": str(directory(payload.get("export_dir") or store.prefs()["download_dir"])), "resource_policy": current["effective_policy"], "engine": {k: current[k] for k in ("service", "base_url", "model")}}
            options.update(channel_id=selected['id'],channel_name=selected['name'],channel_revision=selected.get('revision',1),source_directory=file.get('source_directory',''),save_mode=payload.get('save_mode',store.prefs().get('save_mode','custom')))
            if options['save_mode'] not in {'custom','source'}:raise HTTPException(400,'请选择有效的保存方式。')
            if options['save_mode']=='source':
                if not options['source_directory']:raise HTTPException(400,'无法确定源文件目录，请重新从本地导入 PDF。')
                options['export_dir']=str(directory(options['source_directory']))
            cli=legacy._cli_settings()
            options["term_credential_provider"]=next((meta.translate_engine_type for meta in TRANSLATION_ENGINE_METADATA if getattr(cli,"term_"+meta.cli_flag_name,False)),None)
        if not re.fullmatch(r"[a-zA-Z]{2,3}(?:-[a-zA-Z]{2,4})?", options["lang_out"]) or options["lang_out"] == "auto": raise HTTPException(400, "请选择明确的目标语言。")
        if options["lang_in"] != "auto" and not re.fullmatch(r"[a-zA-Z]{2,3}(?:-[a-zA-Z]{2,4})?", options["lang_in"]): raise HTTPException(400, "源语言无效。")
        if options["no_dual"] and options["no_mono"]: raise HTTPException(400, "至少保留一种输出。")
        if options["pages"] and not re.fullmatch(r"[0-9,\-\s]+", options["pages"]): raise HTTPException(400, "页码范围无效，例如 1,3,5-10。")
        with settings_lock:
            model = build_settings(options)
            options["auto_term_extraction"]=not model.translation.no_auto_extract_glossary
            if "settings_snapshot" not in options: options.update(freeze(model,home))
        payload_hash = fingerprint({"file_sha256": file["sha256"], "options": options, "parent_task_id": parent})
        task, fresh = store.create(key, payload_hash, file, options, parent,request_fingerprint(payload,file["sha256"],parent))
        if fresh:
            model.translation.output = str(work/"outputs"/task["id"])
            engine.submit(task["id"], model.model_dump(mode="json"), options["resource_policy"])
        return store.public(task)

    @app.post("/api/tasks")
    def create(payload: dict, idempotency_key: str | None = Header(default=None)): return submit(payload, idempotency_key)

    @app.get("/api/tasks")
    def tasks():
        page = store.history(); return page["active"]+page["history"]

    @app.get("/api/history")
    def history(cursor: str | None = None, limit: int = 50): return store.history(cursor, limit)

    @app.get("/api/tasks/{ident}")
    def task(ident: str): return store.public(require_task(ident))

    @app.get("/api/tasks/{ident}/configuration")
    def task_configuration(ident:str):
        options=require_task(ident)["options"].copy();options.pop("credential_fields",None);return options

    @app.post("/api/tasks/{ident}/cancel")
    def cancel(ident: str): require_task(ident); return store.public(store.cancel(ident))

    @app.post("/api/tasks/{ident}/retry")
    def retry(ident: str, idempotency_key: str | None = Header(default=None)):
        if idempotency_key and store.lookup(idempotency_key,ident):return submit({},idempotency_key,ident)
        original = require_task(ident)
        if original["status"] not in {"failed", "cancelled"}: raise HTTPException(409, "只能重试失败或已取消的任务。")
        return submit({}, idempotency_key, ident, original)

    @app.delete("/api/tasks")
    def clear(): store.clear(); return {"cleared": "terminal_only"}

    @app.post("/api/tasks/{ident}/export")
    def export(ident: str, payload: dict):
        options=require_task(ident)['options'];mode=payload.get('save_mode',options.get('save_mode','custom'))
        if mode not in {'custom','source'}:raise HTTPException(400,'请选择有效的保存方式。')
        destination=payload.get('directory') or options.get('export_dir') or store.prefs()['download_dir']
        if mode=='source':
            if not options.get('source_directory'):raise HTTPException(400,'该历史任务没有源目录，请选择另存目录或重新导入。')
            destination=options['source_directory']
        return store.public(exports.save(ident,destination,payload['export_id'],alongside=mode=='source',kinds=payload.get('kinds')))

    @app.post("/api/export-receipts")
    def receipt(payload: dict): return exports.receipt(payload)

    @app.get("/api/glossary")
    def glossary(): return legacy.list_glossary()

    @app.post("/api/glossary")
    async def upload_glossary(file: UploadFile = File(...)):
        def update():
            with settings_lock:return asyncio.run(legacy.api_upload_glossary(file))
        return await asyncio.to_thread(update)

    @app.delete("/api/glossary/{source}")
    def delete_glossary(source: str, file: str | None = None):
        with settings_lock:return legacy.api_delete_glossary(source,file)

    threading.Thread(target=assets.verify, daemon=True).start()
    return app


def main():
    home = Path(os.environ["PDF2ZH_HOME"]).resolve()
    owner = DataOwner(home)
    boot = json.loads(sys.stdin.readline())
    token = boot["token"]
    if not isinstance(token, str) or len(token)<32: raise ValueError("会话凭据无效")
    legacy_root = os.environ.get("PDF2ZH_LEGACY_ROOT", str(home))
    migrate_config(home, legacy_root,protect_backup=True)
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0)); listener.listen(128)
    port = listener.getsockname()[1]
    app = create_app(home, token, port, boot["downloads"], legacy_root=legacy_root)
    import uvicorn
    config = uvicorn.Config(app, host="127.0.0.1", port=port, access_log=False, log_level="error", log_config=None,timeout_graceful_shutdown=8)
    server = uvicorn.Server(config)
    def parent_lifetime():
        # Parent disappearing closes stdin; job ownership is the primary guard.
        # A blocking TextIOWrapper.read holds its lock for the entire session.
        # Use the raw descriptor so child bootstrap/stdio cleanup never waits
        # for that Python stream lock.
        descriptor = sys.stdin.fileno()
        while os.read(descriptor, 4096): pass
        server.should_exit = True
    threading.Thread(target=parent_lifetime, daemon=True).start()
    print(json.dumps({"port": port, "pid": os.getpid()}), flush=True)
    try: server.run(sockets=[listener])
    finally: owner.close(); listener.close()


if __name__ == "__main__": main()
