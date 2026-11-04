"""Read-only payload audit. Uses stdlib only; never imports product modules."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import stat
import time

parser = argparse.ArgumentParser()
parser.add_argument("--repo", type=Path, required=True)
parser.add_argument("--build", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
repo, build = args.repo.resolve(), args.build.resolve()
if args.output.exists():
    raise SystemExit("Refuse observation reuse")
load = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

report = load(build/"build-report.json")
payload = Path(report["payload"])
files, reparse = {}, []
for root, dirs, names in os.walk(payload, followlinks=False):
    for name in list(dirs):
        path = Path(root)/name
        if path.lstat().st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            reparse.append(str(path)); dirs.remove(name)
    for name in names:
        path = Path(root)/name
        if path.lstat().st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            reparse.append(str(path)); continue
        files[path.relative_to(payload).as_posix()] = path

entries, seen, unsafe, duplicates = {}, set(), [], []
for line in (payload/"owned-files.tsv").read_text(encoding="utf-8-sig").splitlines():
    name, digest = line.rsplit("|", 1)
    win = PureWindowsPath(name)
    if win.is_absolute() or ".." in win.parts:
        unsafe.append(name); continue
    name = win.as_posix()
    if name.casefold() in seen: duplicates.append(name)
    seen.add(name.casefold())
    entries[name] = digest
missing = sorted(set(entries)-set(files))
extra = sorted(set(files)-set(entries)-{"owned-files.tsv"})
bad = [name for name,digest in entries.items() if name in files and sha(files[name]).lower()!=digest.lower()]
source = load(build/"product-source.json")
source_bad = []
for row in source["files"]:
    for side in ("source", "packaged"):
        path = Path(row[side])
        path.resolve().relative_to(repo)
        if sha(path).lower()!=row["sha256"].lower():source_bad.append({"side":side,"path":str(path)})
package = payload/"uv-tools/pdf2zh-next/Lib/site-packages/pdf2zh_next"
expected = {row["relative"] for row in source["files"]}
actual = {p.relative_to(package).as_posix() for p in package.rglob("*") if p.is_file()}
identity = {"build_report":sha(build/"build-report.json"),"manifest":sha(payload/"owned-files.tsv"),"source_report":sha(build/"product-source.json"),"installer":sha(Path(report["installer"]))}
bindings = {
    "manifest":identity["manifest"].upper()==report["owned_manifest_sha256"],
    "source_report":identity["source_report"].upper()==report["product_source_report_sha256"],
    "installer":identity["installer"].upper()==report["installer_sha256"] and Path(report["installer"]).stat().st_size==report["installer_bytes"],
    "python_lock":sha(repo/"build/dependency-locks/windows-py312.txt").upper()==report["lock_sha256"],
    "patch_lock":sha(repo/"build/patches/babeldoc/patch-lock.json").upper()==report["patch_lock_sha256"],
    "nuget_lock":sha(repo/"desktop/PDFMathTranslate.Desktop/packages.lock.json").upper()==report["nuget_lock_sha256"],
}
licenses = {}
for name in ("XamlFlair-LICENSE.txt","System.Reactive-LICENSE.txt","Microsoft.Extensions-LICENSE.txt","Microsoft.Extensions-NOTICE.txt"):
    path = payload/"licenses"/name
    licenses[name] = {"sha256":sha(path),"matches_vendored_bytes":sha(path)==sha(repo/"build/licenses"/name)}
mit = (payload/"licenses/Microsoft.Extensions-LICENSE.txt").read_text(encoding="utf-8-sig")
notice = (payload/"licenses/Microsoft.Extensions-NOTICE.txt").read_text(encoding="utf-8-sig")
license_source_ok = licenses["Microsoft.Extensions-LICENSE.txt"]["sha256"].upper()=="CFC21F5E8BD655AE997EEC916138B707B1D290B83272C02A95C9F821B8C87310" and "MIT License" in mit and "b0f34d51fccc69fd334253924abd8d6853fad7aa" in notice and "Microsoft Corporation" in notice
deps = load(payload/"PDFMathTranslate.deps.json")
result = {
    "scope":"Independent read-only complete new payload and vendored license identity; NuGet archive-content check is separate",
    "checked_unix":time.time(),"source_commit":report["source_commit"],"copy_source_commit":source["source_commit"],"source_dirty_reported":report["source_dirty"],
    "payload_files":len(files),"payload_bytes":sum(p.stat().st_size for p in files.values()),"manifest_rows":len(entries),"manifest_missing":missing,"manifest_extra_except_self":extra,"manifest_hash_mismatch":bad,"manifest_unsafe":unsafe,"manifest_duplicates":duplicates,"reparse_entries":reparse,
    "python_source_files":len(source["files"]),"python_source_hash_mismatch":source_bad,"python_source_missing":sorted(expected-actual),"python_source_extra":sorted(actual-expected),
    "identity":identity,"report_bindings_match":bindings,"licenses":licenses,"extensions_license_and_notice_source_match":license_source_ok,"version":load(payload/"version.json"),"source_link_runtime_libraries":[name for name in deps["libraries"] if "SourceLink" in name or "Build.Tasks.Git" in name],
}
result["passed"] = not any((missing,extra,bad,unsafe,duplicates,reparse,source_bad,expected-actual,actual-expected)) and all(bindings.values()) and all(v["matches_vendored_bytes"] for v in licenses.values()) and license_source_ok and len(files)==report["payload_files"] and result["payload_bytes"]==report["payload_bytes"]
args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({key:result[key] for key in ("passed","source_commit","payload_files","payload_bytes","manifest_rows","manifest_missing","manifest_extra_except_self","manifest_hash_mismatch","extensions_license_and_notice_source_match","identity")},ensure_ascii=True,indent=2))
