"""Derive bounded observed process counters; do not invent missed child CPU."""
import argparse, hashlib, json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('samples', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
if args.output.exists(): raise RuntimeError('refuse to replace derived evidence')
data = json.loads(args.samples.read_text(encoding='utf-8-sig'))
samples = data['samples']
identities = {}
for sample in samples:
    for process in sample['processes']:
        identities.setdefault((process['pid'], process['created']), []).append(process)
metrics = {name: sum(max(p[name] for p in rows)-min(p[name] for p in rows) for rows in identities.values())
           for name in ('cpu_seconds', 'read_bytes', 'write_bytes')}
result = {'scope': data['scope'], 'input_sha256': hashlib.sha256(args.samples.read_bytes()).hexdigest(),
          'samples': len(samples), 'seconds': samples[-1]['ts']-samples[0]['ts'],
          'observed_process_identities': len(identities), 'observed_counter_deltas': metrics,
          'tree_private_peak_bytes': max(sum(p['private_bytes'] for p in s['processes']) for s in samples),
          'tree_working_set_peak_bytes': max(sum(p['working_set_bytes'] for p in s['processes']) for s in samples),
          'tree_threads_peak': max(sum(p['threads'] for p in s['processes']) for s in samples),
          'final_observed_processes': samples[-1]['processes'],
          'limits': '250ms polling can miss short-lived processes and their initial/final counters; deltas are observed lower bounds, not full accounting. Includes API lifecycle and previews, not just translation. GPU unmeasured.'}
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
