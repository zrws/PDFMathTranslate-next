"""Read-only PyMuPDF extraction of owned fixture pages; visual rendering is separate."""
import hashlib
import json
import re
from pathlib import Path
import pymupdf

repo=Path(__file__).resolve().parents[4]
out=Path(__file__).resolve().parent
target=out/'pdf-body-review.json'
if target.exists():raise SystemExit('Refuse observation reuse')
audit_path=repo/'docs/verification/native-desktop/channels-delivery-20261104-a329045/pdf-body-audit.json'
audit=json.loads(audit_path.read_text(encoding='utf-8-sig'))
text_dir=out/'pdf-text';text_dir.mkdir()
phrase='科学论文译文保留公式与页面结构，逐页记录实验结果和有效配置。'
normalize=lambda text:re.sub(r'\s+','',text)
records=[]
for record in audit['records']:
    path=repo/record['copy']
    raw=path.read_bytes()
    doc=pymupdf.open(path)
    pages=[]
    for number,page in enumerate(doc,1):
        text=page.get_text(sort=True)
        normalized=normalize(text)
        text_file=text_dir/(path.stem+f'-page-{number}.txt')
        text_file.write_text(text,encoding='utf-8')
        body_blocks=[]
        for block in page.get_text('blocks'):
            if len(block)>4 and '科学论文译文' in normalize(block[4]):
                body_blocks.append({'bbox':list(block[:4]),'text':block[4]})
        pages.append({'page':number,'width':page.rect.width,'height':page.rect.height,
                      'fixture_body_present':normalize(phrase) in normalized,
                      'fixture_body_occurrences':normalized.count(normalize(phrase)),
                      'formula_E_equals_mc_squared_present':'E=mc^2' in normalized,
                      'original_unique_page_marker_present':f'Uniquepage{number}marker.' in normalized,
                      'body_blocks':body_blocks,'text_file':text_file.relative_to(repo).as_posix()})
    source=record['role']=='source-original'
    records.append({'role':record['role'],'copy':record['copy'],'sha256':hashlib.sha256(raw).hexdigest(),
                    'recorded_hash_matches':hashlib.sha256(raw).hexdigest()==record['sha256'],
                    'page_count_matches':len(doc)==record['pages'],'pages':pages,
                    'all_pages_have_fixture_body':None if source else all(p['fixture_body_present'] for p in pages),
                    'all_pages_have_formula':all(p['formula_E_equals_mc_squared_present'] for p in pages)})
result={'scope':'Independent per-page owned fixture body and formula extraction; exact loopback response, not provider translation-quality proof; text extraction does not alone prove layout fidelity',
        'pymupdf_version':pymupdf.__version__,'pymupdf_module':pymupdf.__file__,
        'audit_sha256':hashlib.sha256(audit_path.read_bytes()).hexdigest(),'expected_fixture_body':phrase,'records':records}
result['passed']=all(r['recorded_hash_matches'] and r['page_count_matches'] and r['all_pages_have_formula'] and (r['all_pages_have_fixture_body'] is not False) for r in records)
target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':result['passed'],'pdf_records':len(records),'pages_extracted':sum(len(r['pages']) for r in records),
                  'missing_formula_pages':[(r['copy'],p['page']) for r in records for p in r['pages'] if not p['formula_E_equals_mc_squared_present']],
                  'missing_translated_body_pages':[(r['copy'],p['page']) for r in records if r['role']!='source-original' for p in r['pages'] if not p['fixture_body_present']]},ensure_ascii=True,indent=2))
