"""测试会话隔离引导（P0 整改 R6）。

pdf2zh_next.const 在包导入时即对 ``~/.config/pdf2zh`` 执行 mkdir；
``translator.cache.init_db`` 使用 ``Path.home()/.cache/pdf2zh_next``；
``http_api.WORK_DIR`` 依赖进程 CWD。若不隔离，pytest 直接导入这些模块会
写入真实用户目录。

本 conftest 在任何 pdf2zh_next 导入之前把 HOME/USERPROFILE 等仅限**本
pytest 进程**重定向到唯一的临时隔离目录，并把 CWD 切到其中的 work/。
不修改系统或用户级环境；隔离目录不自动删除，便于核对。
隔离根路径会在 pytest 会话头部打印，供证据留档。
"""

import os
import tempfile
from pathlib import Path

_iso_root = Path(tempfile.mkdtemp(prefix="pdf2zh-pytest-"))
(_iso_root / "home").mkdir(parents=True, exist_ok=True)
(_iso_root / "work").mkdir(parents=True, exist_ok=True)
_iso_home = _iso_root / "home"

# 与 start-webui.py 的隔离约定保持一致；其中 HOME/USERPROFILE 是 const.py
# 与 cache.py 实际读取的来源，必须在首次导入 pdf2zh_next 之前生效。
os.environ["PDF2ZH_HOME"] = str(_iso_root)
os.environ["HOME"] = str(_iso_home)
os.environ["USERPROFILE"] = str(_iso_home)
os.environ["APPDATA"] = str(_iso_home / "AppData" / "Roaming")
os.environ["LOCALAPPDATA"] = str(_iso_home / "AppData" / "Local")
os.environ["XDG_CACHE_HOME"] = str(_iso_home / ".cache")
# R2: 继承的 PDF2ZH_CONFIG_FILE 可能指向真实用户配置；const.py 读取它时
# 优先级高于 HOME 派生路径，必须强制指向隔离目录内的新空配置。
_cfg_dir = _iso_root / "home" / ".config" / "pdf2zh"
_cfg_dir.mkdir(parents=True, exist_ok=True)
_iso_config = _cfg_dir / "config.v3.toml"
if not _iso_config.exists():
    _iso_config.write_text("", encoding="utf-8")
os.environ["PDF2ZH_CONFIG_FILE"] = str(_iso_config)
_tmp_dir = _iso_root / "tmp"
_tmp_dir.mkdir(parents=True, exist_ok=True)
os.environ["TEMP"] = str(_tmp_dir)
os.environ["TMP"] = str(_tmp_dir)

# WORK_DIR = Path("pdf2zh_files").resolve()：CWD 决定任务历史/上传/输出位置
os.chdir(_iso_root / "work")


def pytest_configure(config):
    print(f"\n[pdf2zh-test-isolation] root={_iso_root}")
    print(f"[pdf2zh-test-isolation] cwd={os.getcwd()}")
    print(f"[pdf2zh-test-isolation] config={os.environ.get('PDF2ZH_CONFIG_FILE')}")
    _ru = os.environ.get("USERPROFILE", "")
    _rh = os.environ.get("HOME", "")
    _real = os.path.expanduser("~")
    leaked = (_ru and not _ru.startswith(str(_iso_root))) or (_rh and not _rh.startswith(str(_iso_root)))
    if leaked:
        print(f"[pdf2zh-test-isolation][FAIL] home not isolated: USERPROFILE={_ru} HOME={_rh} expanduser={_real}")
    else:
        print("[pdf2zh-test-isolation][ok] HOME/USERPROFILE fully inside the isolated root")
