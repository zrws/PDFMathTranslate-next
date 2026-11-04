"""Kernel ownership and identity checks for the local acceptance driver only."""
import ctypes
from ctypes import wintypes
import os
import threading
from collections import Counter
import psutil


class Basic(ctypes.Structure):
    _fields_ = [("process_time", ctypes.c_int64), ("job_time", ctypes.c_int64), ("flags", wintypes.DWORD), ("min", ctypes.c_size_t), ("max", ctypes.c_size_t), ("active", wintypes.DWORD), ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD), ("scheduling", wintypes.DWORD)]


class Io(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in ("read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]


class Limits(ctypes.Structure):
    _fields_ = [("basic", Basic), ("io", Io), ("process_memory", ctypes.c_size_t), ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]


class OwnedJob:
    def __init__(self, child):
        if os.name != "nt": raise RuntimeError("Windows Job required for this Windows acceptance driver")
        self.lock = threading.Lock()
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        for name, args, result in [
            ("CreateJobObjectW", [ctypes.c_void_p, wintypes.LPCWSTR], wintypes.HANDLE),
            ("SetInformationJobObject", [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD], wintypes.BOOL),
            ("AssignProcessToJobObject", [wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            ("OpenProcess", [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
            ("IsProcessInJob", [wintypes.HANDLE, wintypes.HANDLE, ctypes.POINTER(wintypes.BOOL)], wintypes.BOOL),
            ("CloseHandle", [wintypes.HANDLE], wintypes.BOOL),
        ]:
            call = getattr(self.kernel, name); call.argtypes = args; call.restype = result
        self.handle = self.kernel.CreateJobObjectW(None, None)
        limits = Limits(); limits.basic.flags = 0x2000  # KILL_ON_JOB_CLOSE; non-inherited handle.
        if not self.handle or not self.kernel.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)) or not self.kernel.AssignProcessToJobObject(self.handle, int(child._handle)):
            error = ctypes.get_last_error(); self.close()
            raise OSError(error, "Cannot establish acceptance-owned Job before bootstrap")

    def contains(self, pid):
        with self.lock:
            if not self.handle: return False
            handle = self.kernel.OpenProcess(0x1000, False, pid)
            if not handle: return False
            try:
                member = wintypes.BOOL()
                return bool(self.kernel.IsProcessInJob(handle, self.handle, ctypes.byref(member)) and member.value)
            finally: self.kernel.CloseHandle(handle)

    def close(self):
        with self.lock:
            if self.handle:
                handle, self.handle = self.handle, None
                if not self.kernel.CloseHandle(handle): raise ctypes.WinError(ctypes.get_last_error())


def canonical(path): return os.path.normcase(os.path.abspath(path))


def identity(process): return process.pid, process.create_time(), canonical(process.exe())


def sample_owned(root, job, allowed_images):
    """Never emit a candidate until live parent, child and kernel ownership agree."""
    records, rejected = [], Counter()
    pending = [(root, None)]; seen = set()
    while pending:
        expected, parent_identity = pending.pop()
        if expected[:2] in seen: continue
        seen.add(expected[:2])
        try:
            process = psutil.Process(expected[0])
            if identity(process) != expected or not job.contains(process.pid):
                rejected["changed_identity_or_not_job_member"] += 1; continue
            if parent_identity is not None:
                parent = psutil.Process(parent_identity[0])
                if identity(parent) != parent_identity or process.ppid() != parent.pid or expected[1] < parent_identity[1]:
                    rejected["stale_parent_or_child"] += 1; continue
            memory = process.memory_info(); cpu = process.cpu_times(); io = process.io_counters()
            row = {"pid":process.pid,"created":expected[1],"exe":expected[2],"name":process.name(),"job_member":True,
                   "parent_pid":parent_identity[0] if parent_identity else None,"parent_created":parent_identity[1] if parent_identity else None,
                   "private_bytes":memory.private,"working_set_bytes":memory.rss,"threads":process.num_threads(),
                   "cpu_seconds":cpu.user+cpu.system,"read_bytes":io.read_bytes,"write_bytes":io.write_bytes}
            if identity(process) != expected: rejected["identity_changed_during_metrics"] += 1; continue
            if parent_identity is not None and identity(psutil.Process(parent_identity[0])) != parent_identity:
                rejected["parent_changed_during_metrics"] += 1; continue
            records.append(row)
            for child in process.children(recursive=False):
                try:
                    candidate = identity(child)
                    if candidate[1] < expected[1] or child.ppid() != process.pid:
                        rejected["child_predates_parent_or_changed_parent"] += 1; continue
                    if candidate[2] not in allowed_images:
                        rejected["unexpected_image"] += 1; continue
                    if identity(process) != expected or identity(child) != candidate or not job.contains(child.pid):
                        rejected["candidate_changed_or_not_job_member"] += 1; continue
                    pending.append((candidate, expected))
                except (psutil.NoSuchProcess, psutil.AccessDenied): rejected["candidate_exited_or_inaccessible"] += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied): rejected["process_exited_or_inaccessible"] += 1
    return records, dict(rejected)
