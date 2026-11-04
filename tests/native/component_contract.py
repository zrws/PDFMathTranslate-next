"""Enforce the user's library-only native presentation boundary, not legacy HTML."""
import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree as ET


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[2]
    root=repo/'desktop/PDFMathTranslate.Desktop'
    output=args.output.resolve()
    allowed=(repo/'docs/verification/native-desktop').resolve()
    if not output.is_relative_to(allowed) or output.exists():
        raise SystemExit('Output must be a new file under this repository verification directory')
    ui='http://schemas.lepo.co/wpfui/2022/xaml'
    motion='clr-namespace:XamlFlair;assembly=XamlFlair.WPF'
    wpf='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    counts=Counter()
    violations=[]
    files=[]
    forbidden={'Style','Setter','ControlTemplate','Storyboard','DoubleAnimation','ColorAnimation','SolidColorBrush','LinearGradientBrush','RadialGradientBrush','Path','Canvas','Border'}
    for path in sorted(root.glob('*.xaml')):
        document=ET.parse(path).getroot()
        files.append({'path':str(path.relative_to(repo)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        if document.tag=='{'+wpf+'}Page':
            if not any(node.get('{'+motion+'}Animations.Primary')=='{Binding Appearance.EntranceAnimation}' for node in document.iter()):
                violations.append(f'{path.name}: missing actual motion-library binding')
        for node in document.iter():
            tag=node.tag.split('}')[-1]
            if tag in forbidden:violations.append(f'{path.name}: application-authored {tag}')
            if node.tag.startswith('{'+ui+'}'):counts[tag]+=1
            if node.tag=='{'+wpf+'}Button':violations.append(f'{path.name}: unqualified action control')
            if node.get('Style') or node.get('Template'):violations.append(f'{path.name}: overrides component presentation')
    if list(root.glob('*.css')):violations.append('Native UI contains CSS')
    project=ET.parse(root/'PDFMathTranslate.Desktop.csproj').getroot()
    packages={node.get('Include'):node.get('Version') for node in project.iter('PackageReference')}
    for name,version in {'WPF-UI':'[4.3.0]','XamlFlair.WPF':'[1.2.13]'}.items():
        if packages.get(name)!=version:violations.append('Required exact package missing: '+name)
    required={'NavigationView','Card','CardControl','CardAction','CardExpander','Badge','InfoBar','ToggleSwitch','DataGrid','PasswordBox'}
    if required-counts.keys():violations.append('Missing component families: '+str(sorted(required-counts.keys())))
    for path in sorted(root.glob('*.cs'))+sorted(root.glob('*.csproj'))+sorted(root.glob('packages.lock.json')):
        files.append({'path':str(path.relative_to(repo)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    report={'passed':not violations,'completed_at':datetime.now().astimezone().isoformat(),'scope':'native WPF presentation only; existing legacy webui CSS is preserved','component_counts':dict(sorted(counts.items())),'packages':packages,'violations':violations,'source_files':files}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':report['passed'],'violations':violations,'report':str(output)},ensure_ascii=False))
    return 0 if report['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
