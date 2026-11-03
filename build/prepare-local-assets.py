"""Explicit online environment preparation, never called by offline P0 tests."""
import argparse
import json
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="准备项目专用 BabelDOC 资源，不使用用户缓存")
    parser.add_argument("--runtime-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.runtime_root.resolve()
    home = root / "home"
    for name, value in {
        "HOME": home,
        "USERPROFILE": home,
        "APPDATA": home / "AppData/Roaming",
        "LOCALAPPDATA": home / "AppData/Local",
        "XDG_CACHE_HOME": home / ".cache",
        "PDF2ZH_HOME": home,
        "TEMP": root / "tmp",
        "TMP": root / "tmp",
    }.items():
        value.mkdir(parents=True, exist_ok=True)
        os.environ[name] = str(value)
    config = home / ".config/pdf2zh/config.v3.toml"
    config.parent.mkdir(parents=True, exist_ok=True)
    if not config.exists():
        config.write_text("", encoding="utf-8")
    os.environ["PDF2ZH_CONFIG_FILE"] = str(config)
    os.environ["BABELDOC_ASSETS_UPSTREAM"] = "modelscope"
    work = root / "prepare-work"
    work.mkdir(exist_ok=True)
    os.chdir(work)
    import babeldoc.assets.assets as assets
    from babeldoc.const import CACHE_FOLDER

    print(json.dumps({"phase": "online-resource-preparation", "cache": str(CACHE_FOLDER), "home": str(home)}), flush=True)
    assets.warmup()
    manifest = assets.generate_all_assets_file_list()
    (root / "asset-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("Resource preparation completed; offline acceptance still required.", flush=True)


if __name__ == "__main__":
    main()
