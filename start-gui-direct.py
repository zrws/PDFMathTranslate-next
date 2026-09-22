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


def main() -> int:
    root = Path(__file__).resolve().parent
    portable_home = root / "home"
    try:
        portable_home.mkdir(parents=True, exist_ok=True)
        _probe = portable_home / ".write-probe"
        _probe.write_text("ok", encoding="utf-8")
        _probe.unlink()
    except Exception:
        import os as _os

        portable_home = Path(_os.environ.get("LOCALAPPDATA") or str(Path.home())) / "PDFMathTranslate"
        portable_home.mkdir(parents=True, exist_ok=True)
    config_file = portable_home / ".config" / "pdf2zh" / "config.v3.toml"
    portable_appdata = portable_home / "AppData"
    portable_local_appdata = portable_appdata / "Local"
    portable_temp = portable_local_appdata / "Temp"
    for directory in (config_file.parent, portable_local_appdata, portable_temp):
        directory.mkdir(parents=True, exist_ok=True)

    # Keep user data, caches, temporary uploads, and settings inside the bundle.
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

    port = _get_port(sys.argv)

    # pdf2zh_next.gui reads CLI-style settings during import.
    sys.argv = [
        "pdf2zh",
        "--config-file",
        str(config_file),
        "--gui",
        "--server-port",
        str(port),
    ]

    print("Warmup BabelDOC assets...", flush=True)
    import babeldoc.assets.assets

    babeldoc.assets.assets.warmup()

    print("Starting PDFMathTranslate-next WebUI...", flush=True)
    from pdf2zh_next import gui

    active_model = gui.settings.openaicompatible_detail.openai_compatible_model
    active_base_url = gui.settings.openaicompatible_detail.openai_compatible_base_url
    print(f"Active model: {active_model}", flush=True)
    print(f"Active base_url: {active_base_url}", flush=True)

    gui.demo.launch(
        server_name="127.0.0.1",
        server_port=port,
        inbrowser=False,
        share=False,
        prevent_thread_lock=True,
        allowed_paths=[str(p) for p in gui.pdf_preview_allowed_paths],
    )

    print(f"WebUI ready: http://127.0.0.1:{port}", flush=True)

    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("WebUI stopped.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
