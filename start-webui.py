"""便携版启动入口：启动新的 Web UI（FastAPI 后端 + webui 静态界面）。

与 ``start-gui-direct.py``（Gradio 旧界面）并列：
- 本脚本 → 新界面（默认，桌面壳使用）
- ``start-gui-direct.py`` → Gradio 旧界面（保留兼容）

环境变量：
- ``PDF2ZH_CONFIG_FILE``：覆盖配置文件路径（便于测试）
- ``PDF2ZH_WEBUI_DIR``：覆盖 webui 静态目录
"""

import os
import sys
import time
from pathlib import Path


def _get_port(argv: list[str]) -> int:
    if "--server-port" not in argv:
        return 7860
    index = argv.index("--server-port")
    try:
        return int(argv[index + 1])
    except (IndexError, ValueError):
        return 7860


def _resolve_home(root: Path) -> Path:
    """选择用户数据目录。

    优先安装目录下的 home/（便携模式）；若安装目录不可写（例如装在
    Program Files 且未提权运行），回退到 %LOCALAPPDATA%\\PDFMathTranslate。
    """
    override = os.environ.get("PDF2ZH_HOME")
    if override:
        return Path(override)

    portable = root / "home"
    try:
        portable.mkdir(parents=True, exist_ok=True)
        probe = portable / ".write-probe"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink()
        return portable
    except Exception:
        base = os.environ.get("LOCALAPPDATA") or str(Path.home())
        fallback = Path(base) / "PDFMathTranslate"
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


def main() -> int:
    root = Path(__file__).resolve().parent
    portable_home = _resolve_home(root)
    config_file = Path(
        os.environ.get(
            "PDF2ZH_CONFIG_FILE",
            str(portable_home / ".config" / "pdf2zh" / "config.v3.toml"),
        )
    )
    portable_appdata = portable_home / "AppData"
    portable_local_appdata = portable_appdata / "Local"
    portable_temp = portable_local_appdata / "Temp"
    for directory in (config_file.parent, portable_local_appdata, portable_temp):
        directory.mkdir(parents=True, exist_ok=True)

    # 用户数据、缓存、临时上传与设置都留在便携目录内
    os.environ["USERPROFILE"] = str(portable_home)
    os.environ["HOME"] = str(portable_home)
    os.environ["APPDATA"] = str(portable_appdata / "Roaming")
    os.environ["LOCALAPPDATA"] = str(portable_local_appdata)
    os.environ["TEMP"] = str(portable_temp)
    os.environ["TMP"] = str(portable_temp)
    os.environ["XDG_CACHE_HOME"] = str(portable_local_appdata / "Cache")
    os.environ["BABELDOC_ASSETS_UPSTREAM"] = os.environ.get(
        "BABELDOC_ASSETS_UPSTREAM", "modelscope"
    )
    os.environ.setdefault("PDF2ZH_WEBUI_DIR", str(root / "webui"))

    port = _get_port(sys.argv)

    # pdf2zh_next 的配置系统读取 CLI 风格参数
    sys.argv = [
        "pdf2zh",
        "--config-file",
        str(config_file),
        "--gui",
        "--server-port",
        str(port),
    ]

    print("Warmup BabelDOC assets...", flush=True)
    try:
        import babeldoc.assets.assets

        babeldoc.assets.assets.warmup()
    except Exception as exc:  # 资产预热失败不阻塞启动
        print(f"BabelDOC warmup skipped: {exc}", flush=True)

    print(f"User data dir: {portable_home}", flush=True)
    print("Starting PDFMathTranslate-next WebUI (new interface)...", flush=True)
    from pdf2zh_next import http_api

    print(f"WebUI ready: http://127.0.0.1:{port}", flush=True)
    http_api.run_server(port=port)

    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("WebUI stopped.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
