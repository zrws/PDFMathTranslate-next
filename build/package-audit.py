"""Record wheel dependency graph; verify test-only removals before packaging."""
import argparse,importlib.metadata,json,re
from pathlib import Path
from packaging.requirements import Requirement


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--site-packages',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    rows=[];test_only={'pytest','pluggy','iniconfig'}
    for dist in importlib.metadata.distributions(path=[str(args.site_packages)]):
        name=dist.metadata['Name'];requires=dist.requires or [];rows.append({'name':name,'version':dist.version,'requires':requires})
        if re.sub('[-_.]+','-',name.lower()) in test_only:continue
        for text in requires:
            dep=Requirement(text)
            if re.sub('[-_.]+','-',dep.name.lower()) in test_only and (dep.marker is None or dep.marker.evaluate({'extra':''})):
                raise RuntimeError('Test dependency is required at runtime: '+name+' -> '+text)
    args.output.write_text(json.dumps({'packages':sorted(rows,key=lambda x:x['name'].lower()),'test_only_removals':sorted(test_only),'video_plugin':'OpenCV FFmpeg video-only plugin; native PDF path uses image operations; verify actual pipeline after removal'},ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':main()
