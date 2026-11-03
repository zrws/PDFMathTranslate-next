import sys, json, os
from babeldoc.assets.assets import generate_all_assets_file_list
from babeldoc.const import CACHE_FOLDER
file_list = generate_all_assets_file_list()
print(json.dumps({
    "file_list": file_list,
    "cache_folder": str(CACHE_FOLDER),
    "babeldoc_version": __import__("babeldoc").__version__,
    "effective_home": os.environ.get("HOME", ""),
    "effective_userprofile": os.environ.get("USERPROFILE", ""),
}))
