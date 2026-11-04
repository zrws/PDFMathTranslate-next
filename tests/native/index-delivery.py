"""Create a new delivery index without altering original run evidence."""
import argparse, datetime, hashlib, json, subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--run', type=Path, action='append', required=True)
parser.add_argument('--exclude-file', type=Path, action='append', default=[])
parser.add_argument('--exclusion-reason', help='Required when excluding an original local evidence file from public delivery')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
if args.output.exists(): raise RuntimeError('index already exists')

def record(path):
    if path.is_symlink() or path.is_junction(): raise RuntimeError(f'reparse evidence: {path}')
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

roots = [root.resolve(strict=True) for root in args.run]
excluded = {path.resolve(strict=True) for path in args.exclude_file}
if excluded and not args.exclusion_reason: raise RuntimeError('explicit exclusion reason required')
for path in excluded:
    if not path.is_file() or not any(path.is_relative_to(root) for root in roots):
        raise RuntimeError('excluded evidence must be an existing file inside an indexed run')
excluded_records = [{**record(path), 'reason': args.exclusion_reason} for path in sorted(excluded)]
runs = []
for root in roots:
    files = sorted(p for p in root.rglob('*') if p.is_file() and p.suffix.lower() != '.exe' and p not in excluded)
    # Executable distribution artifacts remain local; their hashes and sizes
    # are bound by build/installer reports, not added to Git evidence.
    runs.append({'root': str(root), 'files': [record(p) for p in files]})
tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--', 'source', 'desktop', 'build', 'launcher', 'tests/native', 'global.json'])
source = [record(repo / name.decode('utf-8')) for name in tracked.split(b'\0') if name]
result = {'schema': 1, 'generated_utc': datetime.datetime.now(datetime.UTC).isoformat(),
          'source_commit_at_index': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
          'source_files': source, 'runs': runs,
          'excluded_evidence': excluded_records,
          'scope': 'file identity/delivery index, not a new test run or replacement for per-run assertions and actual exit codes',
          'unverified': ['OS input/dialogs/drag-drop/cross-monitor DPI/Geek GUI', 'GPU counters', 'old whole-desktop baseline', 'commercial and long-document quality', 'intermittent 120s worker startup failure root cause']}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'runs': len(runs), 'files': sum(len(r['files']) for r in runs), 'source_files': len(source), 'output_sha256': record(args.output)['sha256']}))
