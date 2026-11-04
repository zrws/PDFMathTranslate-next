"""Scope decision from preserved extraction; does not change PDFs or extraction."""
import hashlib
import json
from pathlib import Path
root=Path(__file__).resolve().parent
source=root/'pdf-body-review.json'
target=root/'pdf-body-scope.json'
if target.exists():raise SystemExit('Refuse observation reuse')
value=json.loads(source.read_text(encoding='utf-8'))
outputs=[r for r in value['records'] if r['role']!='source-original']
result={
    'scope':'Actual page coverage and fixture-body delivery only; no claim of semantic, scientific, formula or complex layout quality',
    'extraction_source':source.name,'extraction_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'strict_formula_verdict_preserved':value['passed'],
    'pdf_count':len(value['records']),'extracted_pages':sum(len(r['pages']) for r in value['records']),
    'translated_or_saved_pdf_count':len(outputs),'translated_or_saved_pages':sum(len(r['pages']) for r in outputs),
    'functional_body_gate_passed':all(r['recorded_hash_matches'] and r['page_count_matches'] and r['all_pages_have_fixture_body'] for r in outputs),
    'formula_preservation_demonstrated':False,
    'formula_missing_in_mono_pages':[p['page'] for r in outputs if r['copy'].endswith('57420c801f80421f_译文.pdf') for p in r['pages'] if not p['formula_E_equals_mc_squared_present']],
    'interpretation':'The deterministic loopback provider returns the same fixture sentence for every translation chunk, including the literal equation text. Exact sentence is present in body blocks on every translated page. Mono lacks the original literal equation on pages 1-7; dual keeps it on the source half. This proves real all-page pipeline/output selection, not formula retention or provider translation quality. No causal claim of product regression.',
    'visual_review':'Poppler page-7 source/mono/dual renders independently viewed; formula replacement visible. Native WPF screenshots are separate in-process renders, not OS input evidence.'
}
target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:result[k] for k in ('functional_body_gate_passed','extracted_pages','translated_or_saved_pages','formula_preservation_demonstrated','formula_missing_in_mono_pages')},ensure_ascii=True))
