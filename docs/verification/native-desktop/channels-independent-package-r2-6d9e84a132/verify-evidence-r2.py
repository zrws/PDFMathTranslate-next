"""Independent local read-only bindings and arbitrary-precision sample derivation."""
import hashlib
import json
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[4]
out = Path(__file__).resolve().parent / "evidence-review-r2.json"
if out.exists():
    raise SystemExit("Refuse observation reuse")
load = lambda p: json.loads(Path(p).read_text(encoding="utf-8-sig"))
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
root = repo / "docs/verification/native-desktop/channels-workflow-d343def72d"
build = repo / "dist/native-0814d6ecd733"
report = load(build / "build-report.json")
source = load(build / "product-source.json")
provenance = load(root / "provenance.json")
result = load(root / "result.json")
ui = load(root / "ui/ui-result.json")
smoke = load(repo / "docs/verification/native-desktop/channels-release-smoke-54096bd29c/result.json")
commit = report["source_commit"]
def git(*args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True, encoding="utf-8").strip()

git_mismatch = []
for row in source["files"]:
    path = Path(row["source"])
    relative = path.relative_to(repo).as_posix()
    if git("hash-object", "--path="+relative, str(path)) != git("rev-parse", commit+":"+relative):
        git_mismatch.append(relative)
native_hash_mismatch, native_git_mismatch = [], []
for row in provenance["native_source_files"]:
    path = repo / row["path"]
    if sha(path) != row["sha256"].lower(): native_hash_mismatch.append(row["path"])
    if git("hash-object", "--path="+row["path"], str(path)) != git("rev-parse", commit+":"+row["path"]):
        native_git_mismatch.append(row["path"])
module_mismatch = [row["path"] for row in provenance["files"] if sha(row["path"]) != row["sha256"].lower()]
tasks = load(root / "ui/actual-tasks.json")
pdf_bad, pdf_count = [], 0
for task in tasks:
    for kind, identity in task["output_identities"].items():
        paths = [identity["path"]]
        if len(task["output_identities"]) == 1: paths += task["saved_paths"]
        for value in paths:
            path = Path(value).resolve()
            path.relative_to(repo)
            pdf_count += 1
            if sha(path) != identity["sha256"].lower() or path.stat().st_size != identity["size_bytes"]:
                pdf_bad.append(str(path))
body = load(repo / "docs/verification/native-desktop/channels-delivery-20261104-a329045/pdf-body-audit.json")
copy_bad = []
for row in body["records"]:
    copy = repo / row["copy"]
    if sha(copy) != row["sha256"].lower() or copy.stat().st_size != row["bytes"] or sha(row["original"]) != row["sha256"].lower():
        copy_bad.append(row["copy"])
raw_path = root / "process-samples.json"
samples = load(raw_path)["samples"]
max_cpu, invalid, unexpected = {}, [], []
expected_python = str(Path(report["payload"]) / "uv-python/cpython-3.12.13-windows-x86_64-none").lower()
for i, sample in enumerate(samples):
    for p in sample["processes"]:
        ident = (p["pid"], p["created"])
        max_cpu[ident] = max(max_cpu.get(ident, 0), p["cpu_seconds"])
        if not p["job_member"] or (p["parent_created"] is not None and p["created"] < p["parent_created"]):
            invalid.append(i)
        exe = p["exe"].lower()
        allowed = exe in {expected_python+"\\python.exe", expected_python+"\\pythonw.exe", "c:\\windows\\system32\\conhost.exe"}
        allowed = allowed or (p["parent_pid"] is None and exe == str(repo / ".local/ui-channels-final/PDFMathTranslate.exe").lower())
        if not allowed: unexpected.append(i)
metrics = {
    "scope": "Job-gated samples only; sampled maxima/lower bounds; summed WS includes shared pages; no baseline or improvement claim",
    "raw_sha256": sha(raw_path), "samples": len(samples),
    "observed_identity_count": len(max_cpu),
    "peak_private_bytes": max(sum(p["private_bytes"] for p in s["processes"]) for s in samples),
    "peak_summed_working_set_bytes": max(sum(p["working_set_bytes"] for p in s["processes"]) for s in samples),
    "peak_threads": max(sum(p["threads"] for p in s["processes"]) for s in samples),
    "observed_cpu_seconds": sum(max_cpu.values()),
    "workflow_wall_seconds": result["finished"]-result["started"],
    "sample_span_seconds": samples[-1]["ts"]-samples[0]["ts"],
    "invalid_job_or_parent_time_count": len(invalid), "unexpected_accepted_image_count": len(unexpected),
}
published = load(root / "owned-process-summary.json")
numeric_metric_keys = ("samples", "observed_identity_count", "peak_private_bytes", "peak_summed_working_set_bytes", "peak_threads", "observed_cpu_seconds", "workflow_wall_seconds")
metric_bad = [k for k in numeric_metric_keys if published[k] != metrics[k]]
if published["raw_sha256"].lower() != metrics["raw_sha256"].lower():metric_bad.append("raw_sha256")
correction = load(root / "derivation-correction.json")
correction_matches = sha(root / correction["invalid_summary_file"]) == correction["invalid_summary_sha256"].lower() and sha(root / correction["replacement_file"]) == correction["replacement_sha256"].lower()
false_ui = [k for k,v in ui.items() if isinstance(v, bool) and not v]
smoke_hash_match = sha(smoke["executable"]) == smoke["executable_sha256"].lower() and sha(Path(report["payload"])/"PDFMathTranslate.dll") == smoke["dll_sha256"].lower()
review = {
    "scope": "Independent read-only final source/Git/runtime evidence and corrected raw sample audit; no app execution",
    "source_commit": commit, "python_source_count": len(source["files"]), "git_normalized_python_mismatch": git_mismatch,
    "native_source_count": len(provenance["native_source_files"]), "native_hash_mismatch": native_hash_mismatch, "git_normalized_native_mismatch": native_git_mismatch,
    "packaged_modules": len(provenance["files"]), "packaged_module_hash_mismatch": module_mismatch,
    "source_mode": provenance["source_mode"], "source_dirty": provenance["source_dirty"], "ui_dll_sha256": ui["ui_dll_sha256"],
    "provenance_binding_matches": sha(root/"provenance.json") == result["provenance_sha256"],
    "outer_actual_exit": result["actual_exit"], "outer_passed": result["passed"], "ui_false_checks": false_ui,
    "survivors": result["surviving_identities"], "observer_errors": result["observer_errors"],
    "task_count": len(tasks), "all_tasks_done": all(t["status"] == "done" for t in tasks),
    "output_and_saved_files_checked": pdf_count, "pdf_output_hash_mismatch": pdf_bad,
    "copied_pdf_count": len(body["records"]), "copied_pdf_hash_mismatch": copy_bad,
    "metrics": metrics, "published_metric_mismatch": metric_bad,
    "invalid_derivation_retained_and_correction_hashes_match": correction_matches,
    "release_smoke_passed": smoke["passed"], "release_actual_exit": smoke["main_actual_exit"],
    "release_controller_terminated": smoke["controller_terminated"], "release_unauthenticated_status": smoke["unauthenticated_health_status"],
    "release_file_hashes_match": smoke_hash_match,
    "reviewer_comparison_correction": {
        "prior_result": "evidence-review.json", "prior_sha256": sha(out.with_name("evidence-review.json")),
        "prior_driver": "verify-evidence.py", "prior_driver_sha256": sha(out.with_name("verify-evidence.py")),
        "reason": "Initial reviewer compared different explanatory scope text and case-sensitive SHA256 rendering. All numeric derivations were equal; original raw/verdict preserved. This rerun compares numeric fields and case-insensitive hash semantics.",
        "published_scope": published["scope"], "numeric_fields_compared": list(numeric_metric_keys),
    },
}
review["passed"] = not any((git_mismatch,native_hash_mismatch,native_git_mismatch,module_mismatch,pdf_bad,copy_bad,invalid,unexpected,metric_bad,false_ui,result["surviving_identities"],result["observer_errors"])) and correction_matches and smoke_hash_match and result["actual_exit"] == 0 and result["passed"] and len(tasks)==4 and review["all_tasks_done"] and review["provenance_binding_matches"] and provenance["source_mode"]=="packaged" and provenance["source_dirty"] is False
out.write_text(json.dumps(review,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({k:review[k] for k in ("passed","python_source_count","native_source_count","packaged_modules","outer_actual_exit","task_count","metrics","published_metric_mismatch")},ensure_ascii=True,indent=2))
