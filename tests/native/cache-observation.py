"""Count files in an owned test home; never copy resource content to evidence."""
import argparse, datetime, json
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('home',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]
home=args.home.resolve(strict=True)
if not home.is_relative_to(repo/'.local'):raise RuntimeError('only an owned local test home is allowed')
if args.output.exists():raise RuntimeError('observation already exists')

def size(path):
    count=total=0;skipped=[];pending=[path] if path.exists() else []
    while pending:
        directory=pending.pop()
        if directory.is_symlink() or directory.is_junction():skipped.append(str(directory.relative_to(home)));continue
        for item in directory.iterdir():
            if item.is_symlink() or item.is_junction():skipped.append(str(item.relative_to(home)));continue
            if item.is_file():count+=1;total+=item.stat().st_size
            elif item.is_dir():pending.append(item)
    return {'files':count,'bytes':total,'reparse_entries_skipped_without_following':skipped}

roles={'resource_payload':home/'.cache/babeldoc','translation_cache':home/'.cache/pdf2zh_next',
       'work_staging':home/'work','desktop_state_and_preferences':home/'config',
       'engine_configuration':home/'.config','temporary_files':home/'tmp'}
result={'home':str(home),'observed_utc':datetime.datetime.now(datetime.UTC).isoformat(),
        'roles':{name:size(path) for name,path in roles.items()},'entire_home':size(home),
        'scope':'post-run files from a generated two-page loopback fixture; resources were copied from a verified offline cache. 352451566 bytes is asset content, not measured HTTP transfer/retry overhead. Work includes retained uploads/results for retry and is not a bounded preview cache.'}
args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
