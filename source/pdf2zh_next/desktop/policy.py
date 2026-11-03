"""Process-local resource budgets; no system/user environment changes."""
import contextlib
import json
import os
import threading
import time


def effective_policy(tier="balanced", requested_qps=4):
    if tier not in {"eco", "balanced", "performance"}:
        raise ValueError("无效的资源档位")
    cpu = os.cpu_count() or 1
    threads, qps, inflight = {"eco": (min(2, cpu), 2, 4), "balanced": (max(1, min(4, cpu-2)), 4, 8), "performance": (max(1, min(8, cpu-2)), 8, 16)}[tier]
    return {"tier": tier, "document_concurrency": 1, "local_compute_threads": threads, "api_qps_cap": min(max(1, int(requested_qps)), qps), "api_inflight_limit": inflight, "preview_concurrency": 1, "gpu": False}


def worker_policy():
    raw = os.environ.get("PDF2ZH_NATIVE_POLICY")
    return json.loads(raw) if raw else None


def apply_engine_budget(settings):
    policy = worker_policy()
    if not policy:
        return
    tr = settings.translation
    tr.qps = min(tr.qps, policy["api_qps_cap"])
    tr.term_qps = min(tr.term_qps or tr.qps, policy["api_qps_cap"])
    tr.pool_max_workers = min(tr.pool_max_workers or policy["api_inflight_limit"], policy["api_inflight_limit"])
    tr.term_pool_max_workers = min(tr.term_pool_max_workers or tr.pool_max_workers, policy["api_inflight_limit"])


_lock = threading.Lock()
_slots = None
_next = 0.0


@contextlib.contextmanager
def request_budget():
    """Shared by main/term translators, including health checks and retries."""
    global _slots, _next
    policy = worker_policy()
    if not policy:
        yield
        return
    with _lock:
        if _slots is None:
            _slots = threading.BoundedSemaphore(policy["api_inflight_limit"])
    with _slots:
        with _lock:
            now = time.monotonic()
            delay = _next-now
            if delay > 0:
                time.sleep(delay)
            _next = max(_next, time.monotonic())+1/policy["api_qps_cap"]
        yield
