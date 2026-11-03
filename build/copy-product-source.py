"""Copy only tracked product files into a fresh owned build directory."""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--target',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
    repo=Path(__file__).resolve().parent.parent;source=repo/'source/pdf2zh_next';target=args.target.absolute()
    if not target.resolve().is_relative_to((repo/'.local').resolve()) or target.name!='pdf2zh_next':raise ValueError('source target outside owned build')
    for parent in [target,*target.parents]:
        if parent==repo:break
        if parent.is_symlink() or parent.is_junction():raise ValueError('source target has reparse ancestor')
    target.mkdir(parents=True,exist_ok=False)
    result=subprocess.run(['git','ls-files','-z','--','source/pdf2zh_next'],cwd=repo,check=True,capture_output=True)
    files=[repo/name.decode('utf-8') for name in result.stdout.split(b'\0') if name]
    if not files:raise ValueError('tracked product source is empty')
    rows=[]
    for path in files:
        for item in [path,*path.parents]:
            if item.is_symlink() or item.is_junction():raise ValueError('product source has reparse component')
            if item==repo:break
        if not path.resolve().is_relative_to(source.resolve()) or not path.is_file():raise ValueError('invalid product source')
        relative=path.relative_to(source);destination=target/relative;destination.parent.mkdir(parents=True,exist_ok=True)
        before=sha(path);shutil.copyfile(path,destination)
        if sha(path)!=before or sha(destination)!=before:raise ValueError('source changed during packaging')
        rows.append({'relative':relative.as_posix(),'source':str(path),'packaged':str(destination),'sha256':before})
    expected={row['relative'] for row in rows};actual={p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file()}
    if actual!=expected:raise ValueError('packaged source file set differs')
    args.report.write_text(json.dumps({'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'files':rows,'exact_set':True},ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':main()
