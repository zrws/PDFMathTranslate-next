"""One document at a time; no scientific imports in the control process."""
import json
import os
import queue
import secrets
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from .storage import file_identity


def chinese_stage(stage):
    text = stage.lower()
    for token, label in (("parse pdf", "解析 PDF"), ("scanned", "检查扫描页"), ("layout", "分析页面布局"), ("table", "分析表格"), ("paragraph", "整理段落"), ("formula", "识别公式与样式"), ("term", "提取术语"), ("translat", "翻译正文"), ("typeset", "排版译文"), ("font", "整理字体"), ("save", "生成 PDF"), ("create", "生成 PDF"), ("merge", "合并输出")):
        if token in text: return label
    return "处理文档"


class Engine:
    def __init__(self, home, store):
        self.home = Path(home)
        self.store = store
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="desktop-document")

    def submit(self, ident, settings, policy):
        def observed(future):
            try: future.result()
            except Exception: self.store.fail(ident,"任务启动或状态保存失败，请检查磁盘空间与运行环境。")
        try:self.executor.submit(self.run, ident, settings, policy).add_done_callback(observed)
        except Exception:
            self.store.fail(ident,"服务正在停止，任务未启动，请重试。")
            raise

    def run(self, ident, settings, policy):
        if not self.store.start(ident): return
        task = self.store.get(ident)
        child = None
        messages = queue.Queue(maxsize=128)
        drained = threading.Event()
        stop_io = threading.Event()
        cancel_input = threading.Event()
        close_input = threading.Event()
        nonce = secrets.token_hex(24)
        prefix = "PDF2ZH_EVENT "+nonce+" "
        finished = None
        failure = None
        cancelled = False
        progress_closed = None
        try:
            child = subprocess.Popen([sys.executable, "-u", "-m", "pdf2zh_next.desktop.worker", "--translate"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", creationflags=0x08000000 if os.name == "nt" else 0)
            started=time.monotonic();last_event=started;engine_started=False
            def write_input():
                try:
                    child.stdin.write(json.dumps({"settings": settings, "file": task["file_path"], "policy": policy, "event_nonce": nonce})+"\n");child.stdin.flush()
                    while not close_input.wait(.1):
                        if cancel_input.is_set():child.stdin.write("cancel\n");child.stdin.flush();break
                    close_input.wait()
                except (OSError,ValueError):pass
                finally:
                    try:child.stdin.close()
                    except OSError:pass
            threading.Thread(target=write_input,daemon=True).start()
            def collect():
                try:
                    while not stop_io.is_set():
                        line = child.stdout.readline(65536)
                        if not line: break
                        if not line.endswith("\n"):
                            while line and not line.endswith("\n"): line = child.stdout.readline(65536)
                            continue
                        if not line.startswith(prefix): continue
                        try: value = json.loads(line[len(prefix):])
                        except ValueError: continue
                        while not stop_io.is_set():
                            try:messages.put(value,timeout=.2);break
                            except queue.Full:pass
                finally:drained.set()
            threading.Thread(target=collect, daemon=True).start()
            while child.poll() is None or not drained.is_set() or not messages.empty():
                current = self.store.get(ident)
                if current["cancel_requested"]:
                    cancelled = True
                    cancel_input.set()
                    try: child.wait(5)
                    except subprocess.TimeoutExpired: child.kill()
                    break
                if progress_closed is not None and time.monotonic()-progress_closed>30:
                    failure="工作进程结束超时，暂存产物已保留，请重试。";child.kill();break
                if not engine_started and time.monotonic()-started>120 or time.monotonic()-last_event>300:
                    failure="引擎启动或响应超时，请检查服务设置后重试。";child.kill();break
                try: event = messages.get(timeout=0.2)
                except queue.Empty: continue
                last_event=time.monotonic()
                if event is None:
                    progress_closed=time.monotonic()
                    close_input.set()
                    continue
                kind = event.get("type")
                if kind == "startup": self.store.update(ident, persist=True, stage=event["stage"], message=event["stage"])
                elif kind == "finish": finished = event["outputs"]
                elif kind == "error": failure = event.get("error", "翻译失败，请检查设置。")
                elif kind in {"progress_start", "progress_update", "progress_end"}:
                    engine_started=True
                    stage = chinese_stage(event.get("stage", ""))
                    finalizing = stage in {"生成 PDF", "合并输出", "整理字体", "排版译文"}
                    self.store.update(ident, phase="finalizing" if finalizing else "running", stage=stage, message=stage, progress=max(0, min(99, float(event.get("overall_progress") or 0))))
            close_input.set()  # release the cancellation listener before interpreter teardown
            try: child.wait(5)
            except subprocess.TimeoutExpired: child.kill(); child.wait(3)
            outputs = {}
            if finished and not failure and not cancelled and child.returncode==0:
                allowed=(self.home/"work/outputs"/ident).resolve()
                options=self.store.get(ident)['options']
                for kind,name in finished.items():
                    if kind=='dual' and options.get('no_dual') or kind=='mono' and options.get('no_mono') or kind=='glossary' and options.get('auto_term_extraction') is False:continue
                    path=Path(name).resolve()
                    if kind not in {"dual","mono","glossary"} or not path.is_relative_to(allowed) or not path.is_file():raise ValueError("引擎输出路径无效")
                    outputs[kind]={"path":str(path),"output_revision":1,**file_identity(path)}
                if not outputs:raise ValueError("翻译引擎未生成输出")
                required={kind for kind,flag in (('dual','no_dual'),('mono','no_mono')) if flag in options and not options[flag]}
                if not required.issubset(outputs):raise ValueError('翻译引擎没有生成全部勾选的 PDF 类型')
            with self.store.lock:
                cancelled = cancelled or self.store.get(ident)["cancel_requested"]
                if cancelled:
                    self.store.update(ident, persist=True, status="cancelled", stage="已取消", message="任务与工作进程已回收", finished_at=time.time())
                elif finished and not failure and child.returncode == 0:
                    self.store.update(ident, persist=True, status="done", phase="finalizing", stage="翻译完成 · 待保存", message="产物已生成，请保存到所选目录", progress=100, outputs=outputs, finished_at=time.time())
                else:
                    self.store.update(ident, persist=True, status="failed", stage="翻译失败", error=failure or "工作进程未正常完成，请检查服务、资源与 PDF 后重试。", message="可按原配置重试", worker_exit=child.returncode, worker_finish_received=bool(finished), finished_at=time.time())
        except Exception:
            if child is not None and child.poll() is None: child.kill(); child.wait(3)
            self.store.fail(ident,"无法完成翻译或保存任务状态，请检查磁盘空间、资源与服务配置。")
        finally:
            stop_io.set();close_input.set()
            if child is not None:
                drained.wait(2)
                child.stdout.close()

    def close(self):
        with self.store.lock:active=[t["id"] for t in self.store.state["tasks"].values() if t["status"] in {"queued","running"}]
        for ident in active:
            try:self.store.cancel(ident)
            except OSError:self.store.fail(ident,"服务已退出，任务中断且状态尚未写入磁盘。")
        self.executor.shutdown(wait=True,cancel_futures=True)
