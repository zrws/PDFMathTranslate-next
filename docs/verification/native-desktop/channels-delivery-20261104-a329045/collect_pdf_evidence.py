"""Read only this owned fixture's PDFs; copy reviewable bytes and verify body text."""
import hashlib,json,re
from pathlib import Path
import pymupdf

repo=Path(__file__).resolve().parents[4]
run=repo/'docs/verification/native-desktop/channels-workflow-d343def72d'
owned=(repo/'.local/channels-workflow-d343def72d').resolve(strict=True)
destination=Path(__file__).parent/'pdf-examples'
destination.mkdir(exist_ok=False)
tasks=json.loads((run/'ui/actual-tasks.json').read_text(encoding='utf-8-sig'))
scenario=json.loads((run/'scenario.json').read_text(encoding='utf-8-sig'))
records=[]
body='科学论文译文保留公式与页面结构'

def collect(path,label,role):
    source=Path(path).resolve(strict=True)
    if not source.is_relative_to(owned) or source.suffix.lower()!='.pdf':
        raise ValueError('Refuse non-owned PDF')
    raw=source.read_bytes();target=destination/label
    with target.open('xb') as stream:stream.write(raw)
    record={'role':role,'original':str(source),'copy':str(target.relative_to(repo)).replace('\\','/'),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
    with pymupdf.open(target) as document:
        text=re.sub(r'\s+','',document[-1].get_text())
        record.update(pages=len(document),last_page_contains_fixture_body=body in text)
        if role!='source-original' and not record['last_page_contains_fixture_body']:
            raise AssertionError('Last page lacks translated fixture body: '+label)
    records.append(record)

for i,path in enumerate(scenario['samples'],1):collect(path,f'论文{i}_原文.pdf','source-original')
for task in tasks:
    for kind,path in task['outputs'].items():
        collect(path,task['id']+'_'+('双语对照' if kind=='dual' else '译文')+'.pdf','generated-output')
    for i,path in enumerate(task['saved_paths'],1):
        if Path(path).resolve().is_relative_to(owned):
            collect(path,task['id']+f'_源目录保存{i}_'+Path(path).name,'source-saved')
report={'scope':'Post-run copies of owned fixture PDFs; exact translated body check, independent of watermark/CJK-only check; not another translation run','workflow_result_sha256':hashlib.sha256((run/'result.json').read_bytes()).hexdigest(),'collector_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'records':records}
(Path(__file__).parent/'pdf-body-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'pdfs':len(records),'body_checks_passed':True}))
