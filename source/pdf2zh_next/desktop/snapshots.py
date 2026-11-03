"""Immutable effective settings, with credential values kept out of history."""
import copy
import json
import re
import shutil
from pathlib import Path
from .storage import file_identity, fingerprint
from pdf2zh_next.config.translate_engine_model import GUI_PASSWORD_FIELDS

SECRET = re.compile(r"api[_-]?key|password|token|secret|credential|authorization|cookie|access[_-]?key|auth[_-]?key", re.I)


def freeze(settings, home):
    value = settings.model_dump(mode="json")
    value["basic"]["input_files"] = []
    value["translation"]["output"] = None
    credentials = []
    def scrub(node, path=()):
        if isinstance(node, dict):
            for key, child in list(node.items()):
                if key in GUI_PASSWORD_FIELDS or SECRET.search(key):
                    credentials.append(list(path+(key,)));node[key] = None
                else: scrub(child, path+(key,))
        elif isinstance(node, list):
            for index, child in enumerate(node): scrub(child, path+(index,))
    scrub(value)
    glossaries = []
    copies = []
    for name in re.split(r"[;,]", settings.translation.glossaries or ""):
        if not name.strip(): continue
        source = Path(name.strip())
        identity = file_identity(source)
        if identity["size_bytes"]>20*1024*1024: raise ValueError("术语表超过 20 MB，请精简后重试。")
        target = Path(home)/"work/glossary-snapshots"/(identity["sha256"]+".csv")
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            temp = target.with_suffix(".partial")
            try:
                with source.open("rb") as src, temp.open("xb") as out: shutil.copyfileobj(src,out,1024*1024)
                if file_identity(temp)!=identity: raise ValueError("术语表在复制时发生变化，请重试。")
                temp.replace(target)
            finally: temp.unlink(missing_ok=True)
        if file_identity(target)!=identity: raise ValueError("术语快照校验失败，未提交任务。")
        glossaries.append({"path": str(target), **identity});copies.append(str(target))
    value["translation"]["glossaries"] = ",".join(copies) or None
    return {"settings_snapshot": value, "credential_fields": credentials, "glossary_fingerprints": glossaries, "settings_fingerprint": fingerprint(value)}


def restore(options, current_credentials):
    snapshot = copy.deepcopy(options["settings_snapshot"])
    fresh = current_credentials.model_dump(mode="json")
    for path in options["credential_fields"]:
        dest = snapshot; source = fresh
        for key in path[:-1]: dest = dest[key]; source = source[key]
        dest[path[-1]] = source[path[-1]]
    for glossary in options["glossary_fingerprints"]:
        if file_identity(glossary["path"]) != {k:glossary[k] for k in ("size_bytes", "sha256")}:
            raise ValueError("术语快照已改变或不可用，请重新导入并创建任务。")
    from pdf2zh_next.config.model import SettingsModel
    return SettingsModel.model_validate(snapshot)
