"""Measure owned WPF/control PIDs; no input automation or user cache access."""
import argparse,json,os,subprocess,time,uuid
from pathlib import Path
import psutil


def sample(pid):
    try:
        process=psutil.Process(pid);memory=process.memory_info();cpu=process.cpu_times();io=process.io_counters()
        children=[]
        for p in process.children(recursive=True):
            try:children.append({"pid":p.pid,"name":p.name(),"exe":p.exe(),"private_bytes":p.memory_info().private})
            except (psutil.NoSuchProcess,psutil.AccessDenied):pass
        return {"pid":pid,"created":process.create_time(),"private_bytes":memory.private,"working_set_bytes":memory.rss,"cpu_seconds":cpu.user+cpu.system,"threads":process.num_threads(),"read_bytes":io.read_bytes,"write_bytes":io.write_bytes,"children":children}
    except psutil.NoSuchProcess:return None


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--ui-exe',type=Path,required=True);parser.add_argument('--evidence-root',type=Path,required=True);args=parser.parse_args()
    root=args.evidence_root.resolve();root.mkdir(parents=True,exist_ok=False)
    runs=[]
    for index in range(3):
        target=root/f"startup-{index+1}";scenario=root/f"scenario-{index+1}.json";duration=300 if index==2 else 1
        scenario.write_text(json.dumps({"output_root":str(target),"idle_seconds":duration}),encoding='utf-8')
        child=subprocess.Popen([str(args.ui_exe.resolve()),'--ui-test',str(scenario)])
        rows=[];ready=None;deadline=time.monotonic()+duration+90
        try:
            while child.poll() is None and time.monotonic()<deadline:
                signal=target/'performance-ready.json'
                if ready is None and signal.exists():ready=json.loads(signal.read_text())
                if ready and not (target/'performance-idle-finished.json').exists():rows.append({"monotonic":time.monotonic(),"utc":time.time(),"system_cpu_percent":psutil.cpu_percent(),"available_memory":psutil.virtual_memory().available,"ui":sample(ready['ui_pid']),"control":sample(ready['control_pid'])})
                time.sleep(1)
            if child.poll() is None:child.kill();raise RuntimeError('native performance window did not finish')
            if child.returncode!=0 or ready is None:raise RuntimeError('native performance window failed')
            runs.append({"index":index+1,"actual_exit":child.returncode,"startup":ready,"rows":rows})
        finally:
            if child.poll() is None:child.kill();child.wait(5)
            (root/f"measurements-{index+1}.json").write_text(json.dumps({"startup":ready,"rows":rows,"actual_exit":child.poll()},indent=2),encoding='utf-8')
    summary={"passed":True,"scope":"Debug real WPF window plus native control; existing local assets; process-cold starts, OS cache not flushed; no Windows input automation","logical_cpus":psutil.cpu_count(),"startup":[r['startup'] for r in runs],"idle_seconds_measured":runs[-1]['rows'][-1]['monotonic']-runs[-1]['rows'][0]['monotonic'],"gpu":"not measured; backend CPU provider policy enforced, GPU default false"}
    for role in ('ui','control'):
        rows=[x[role] for x in runs[-1]['rows'] if x[role]];first,last=rows[0],rows[-1];seconds=summary['idle_seconds_measured']
        summary[role]={"private_bytes_mean":sum(x['private_bytes'] for x in rows)/len(rows),"private_bytes_peak":max(x['private_bytes'] for x in rows),"working_set_bytes_peak":max(x['working_set_bytes'] for x in rows),"threads_max":max(x['threads'] for x in rows),"cpu_seconds_delta":last['cpu_seconds']-first['cpu_seconds'],"cpu_percent_one_core":(last['cpu_seconds']-first['cpu_seconds'])/seconds*100,"read_bytes_delta":last['read_bytes']-first['read_bytes'],"write_bytes_delta":last['write_bytes']-first['write_bytes'],"idle_children":list({p['pid']:p for x in rows for p in x['children']}.values())}
    (root/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(summary,ensure_ascii=False))


if __name__=='__main__':main()
