"""Explicit legacy WebView entry; same private home and exclusive writer lock.

The default distribution launches WPF. This adapter preserves the former API
and download/versioning clients for separately built legacy launchers.
"""
import asyncio
import hmac
import json
import os
import socket
import sys
import threading
from pathlib import Path


def main():
    boot=json.loads(sys.stdin.readline())
    token=boot["token"];port=int(boot["port"])
    if len(token)!=64 or not 1<=port<=65535:raise ValueError("会话启动参数无效")
    # Own the port before imports/config migration and before publishing any
    # ready marker. Never ask the parent to authenticate an unowned listener.
    listener=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):
        listener.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
    try:listener.bind(('127.0.0.1',port));listener.listen(128)
    except BaseException:listener.close();raise
    home=Path(os.environ["PDF2ZH_HOME"]).resolve()
    from .runtime import DataOwner,migrate_config
    owner=DataOwner(home)
    root=Path(os.environ["PDF2ZH_LEGACY_ROOT"]).resolve()
    migrate_config(home,root)
    config=home/".config/pdf2zh/config.v3.toml"
    os.environ["PDF2ZH_CONFIG_FILE"]=str(config)
    os.environ["PDF2ZH_WEBUI_DIR"]=str(root/"webui")
    sys.argv=["pdf2zh","--config-file",str(config),"--gui"]
    from pdf2zh_next.http_api import app
    from fastapi.responses import JSONResponse
    import uvicorn
    expected=f"127.0.0.1:{port}"
    @app.middleware("http")
    async def authenticate(request,call_next):
        if request.headers.get("host")!=expected or request.headers.get("origin") not in (None,"http://"+expected):
            return JSONResponse({"detail":"请求来源不受许可。"},status_code=403)
        auth=request.headers.get("authorization","")
        if len(auth)>4096 or not hmac.compare_digest(auth.encode(),("Bearer "+token).encode()):
            return JSONResponse({"detail":"此兼容界面只能从已认证的桌面窗口访问。"},status_code=401)
        return await call_next(request)
    server=uvicorn.Server(uvicorn.Config(app,host="127.0.0.1",port=port,access_log=False,log_level="error",timeout_graceful_shutdown=8))
    def parent():
        while os.read(sys.stdin.fileno(),4096):pass
        server.should_exit=True
    threading.Thread(target=parent,daemon=True).start()
    async def serve():
        running=asyncio.create_task(server.serve(sockets=[listener]))
        while not server.started and not running.done():await asyncio.sleep(.02)
        if server.started:print(f"WebUI ready: http://{expected}/ [pid:{os.getpid()}]",flush=True)
        await running
    try:asyncio.run(serve())
    finally:listener.close();owner.close()


if __name__=="__main__":main()
