"""Acceptance observer regressions; actual Job uses only this test's processes."""
import json
import subprocess
import sys
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import psutil
from owned_process import OwnedJob, canonical, identity, sample_owned


class FakeProcess:
    def __init__(self, pid, created, exe, parent=0, children=()):
        self.pid=pid; self.created=created; self.image=exe; self.parent=parent; self.descendants=children
    def create_time(self): return self.created
    def exe(self): return self.image
    def ppid(self): return self.parent
    def children(self, recursive=False):
        assert recursive is False
        return self.descendants
    def memory_info(self): return SimpleNamespace(private=1,rss=1)
    def cpu_times(self): return SimpleNamespace(user=0,system=0)
    def io_counters(self): return SimpleNamespace(read_bytes=0,write_bytes=0)
    def num_threads(self): return 1
    def name(self): return 'owned-test-fixture'


class OwnershipTests(unittest.TestCase):
    def fixture(self, child, contains=lambda pid: True):
        root=FakeProcess(1,20,'expected-python',children=[child])
        factory=lambda pid: {1:root,2:child}[pid]
        with patch('owned_process.psutil.Process',side_effect=factory):
            return sample_owned(identity(root),SimpleNamespace(contains=contains),{canonical('expected-python')})

    def test_reused_parent_number_rejects_older_child(self):
        records,rejected=self.fixture(FakeProcess(2,10,'expected-python',parent=1))
        self.assertEqual([r['pid'] for r in records],[1])
        self.assertEqual(rejected['child_predates_parent_or_changed_parent'],1)

    def test_unexpected_image_is_counted_without_metadata(self):
        records,rejected=self.fixture(FakeProcess(2,21,'private-unexpected-fixture',parent=1))
        self.assertEqual(rejected['unexpected_image'],1)
        self.assertNotIn('private-unexpected-fixture',json.dumps(records))

    def test_nonmember_child_is_not_recorded(self):
        records,rejected=self.fixture(FakeProcess(2,21,'expected-python',parent=1),lambda pid:pid==1)
        self.assertEqual([r['pid'] for r in records],[1])
        self.assertEqual(rejected['candidate_changed_or_not_job_member'],1)

    def test_changed_root_identity_is_not_recorded(self):
        root=FakeProcess(1,21,'expected-python')
        with patch('owned_process.psutil.Process',return_value=root):
            records,rejected=sample_owned((1,20,canonical('expected-python')),SimpleNamespace(contains=lambda pid:True),{canonical('expected-python')})
        self.assertEqual(records,[])
        self.assertEqual(rejected['changed_identity_or_not_job_member'],1)

    def test_invalid_target_assignment_fails_closed(self):
        with self.assertRaises(OSError): OwnedJob(SimpleNamespace(_handle=0))

    def test_cached_old_process_object_does_not_pass_fresh_postcheck(self):
        cached=FakeProcess(1,20,'expected-python')
        replacement=FakeProcess(1,21,'expected-python')
        with patch('owned_process.psutil.Process',side_effect=[cached,replacement]):
            records,rejected=sample_owned(identity(cached),SimpleNamespace(contains=lambda pid:True),{canonical('expected-python')})
        self.assertEqual(records,[])
        self.assertEqual(rejected['identity_changed_during_metrics'],1)

    def test_kernel_close_reclaims_nested_child_and_preserves_outside_sentinel(self):
        flags=0x08000000
        sentinel=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'],creationflags=flags)
        root=subprocess.Popen([sys.executable,'-u','-c',
            'import subprocess,sys,time;sys.stdin.readline();p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"]);print(p.pid,flush=True);time.sleep(60)'],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,creationflags=flags)
        job=None; nested=None
        try:
            job=OwnedJob(root)
            self.assertTrue(job.contains(root.pid))
            self.assertFalse(job.contains(sentinel.pid))
            root.stdin.write(b'bootstrap\n');root.stdin.flush()
            nested=psutil.Process(int(root.stdout.readline()))
            nested_identity=identity(nested)
            self.assertTrue(job.contains(nested.pid))
            records,_=sample_owned(identity(psutil.Process(root.pid)),job,{canonical(sys.executable)})
            self.assertEqual({r['pid'] for r in records},{root.pid,nested.pid})
            job.close();root.wait(5)
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                try:
                    if nested.create_time()!=nested_identity[1] or not nested.is_running(): break
                except psutil.NoSuchProcess: break
                time.sleep(.05)
            else: self.fail('kernel-owned nested process survived Job close')
            self.assertIsNone(sentinel.poll())
        finally:
            if job:job.close()
            if root.poll() is None:root.kill()
            root.wait(5)
            root.stdin.close();root.stdout.close()
            if sentinel.poll() is None:sentinel.kill()
            sentinel.wait(5)


if __name__=='__main__': unittest.main(verbosity=2)
