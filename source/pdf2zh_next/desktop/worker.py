"""Spawn target: one real BabelDOC task, primitive IPC, then exit."""
import json
import os
import queue
import sys
import threading
from pathlib import Path


class PrimitivePipe:
    def __init__(self, pipe): self.pipe = pipe
    def send(self, value):
        if isinstance(value, BaseException):
            value = {"type": "error", "error": "翻译引擎执行失败，请检查服务设置、资源及输入 PDF 后重试。", "error_type": type(value).__name__}
        elif isinstance(value, dict) and value.get("type") == "finish":
            result = value["translate_result"]
            value = {"type": "finish", "outputs": {kind: str(path) for kind, path in (("dual", getattr(result, "dual_pdf_path", None)), ("mono", getattr(result, "mono_pdf_path", None)), ("glossary", getattr(result, "auto_extracted_glossary_path", None))) if path}}
        elif isinstance(value, dict):
            value = {k: v for k,v in value.items() if isinstance(v, (str, int, float, bool, type(None)))}
        self.pipe.send(value)
    def close(self): self.pipe.close()


class JsonPipe:
    def __init__(self, nonce): self.prefix = "PDF2ZH_EVENT "+nonce+" "
    def send(self, value):
        print(self.prefix+json.dumps(value, ensure_ascii=False), flush=True)
    def close(self): sys.stdout.flush()


class CancellationInput:
    def recv(self):
        if not os.read(sys.stdin.fileno(), 4096): raise EOFError()
        return "cancel"


class LogQueue(queue.Queue):
    def close(self): pass


def translate(settings_dict, file, policy, progress, cancel):
    progress.send({"type": "startup", "stage": "建立任务进程边界"})
    threads = str(policy["local_compute_threads"])
    for name in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "NUMEXPR_NUM_THREADS", "PDF2ZH_LOCAL_THREADS"):
        os.environ[name] = threads
    os.environ["PDF2ZH_NATIVE_POLICY"] = json.dumps(policy)
    if os.name == "nt":
        import multiprocessing
        windowless_python = Path(sys.executable).with_name("pythonw.exe")
        if not windowless_python.is_file(): raise RuntimeError("缺少无控制台的 Python 子进程入口")
        multiprocessing.set_executable(str(windowless_python))
    # Each task owns a job too; a forced cancellation closes its nested workers.
    job = None
    if os.name == "nt":
        from .windows_job import current_process_job
        job = current_process_job()
    try:
        progress.send({"type": "startup", "stage": "加载图像处理模块"})
        import cv2
        cv2.setNumThreads(policy["local_compute_threads"])
        progress.send({"type": "startup", "stage": "加载翻译与排版模块"})
        from pdf2zh_next.config.model import SettingsModel
        from pdf2zh_next.desktop.policy import apply_engine_budget
        from pdf2zh_next.high_level import _translate_wrapper
        settings = SettingsModel.model_validate(settings_dict)
        apply_engine_budget(settings)
        logs = LogQueue(maxsize=256)
        def drain():
            while True:
                try:
                    if logs.get() is None: return
                except (EOFError, OSError): return
        threading.Thread(target=drain, daemon=True).start()
        progress.send({"type": "policy", "effective_policy": policy})
        progress.send({"type": "startup", "stage": "准备排版模型与服务"})
        _translate_wrapper(settings, Path(file), PrimitivePipe(progress), cancel, logs)
    except Exception as exc:
        try: progress.send({"type": "error", "error": "翻译引擎启动失败，请确认依赖、密钥和资源完整。", "error_type": type(exc).__name__})
        except (EOFError, OSError): pass
    finally:
        # Keep job handle alive until OS teardown; closing it here would kill
        # this process before pipe/queue buffers have drained.
        if job is not None: job.detach()


def assets():
    from babeldoc.assets.assets import warmup
    warmup()


if __name__ == "__main__":
    if "--translate" in sys.argv:
        boot = json.loads(sys.stdin.readline())
        translate(boot["settings"], boot["file"], boot["policy"], JsonPipe(boot["event_nonce"]), CancellationInput())
    else:
        assets()
