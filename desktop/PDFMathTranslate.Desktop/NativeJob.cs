using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PDFMathTranslate.Desktop;

internal static class NativeJob
{
    [StructLayout(LayoutKind.Sequential)] private struct Basic { public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max; public uint Active; public UIntPtr Affinity; public uint Priority, Scheduling; }
    [StructLayout(LayoutKind.Sequential)] private struct Counters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] private struct Limits { public Basic Basic; public Counters Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(SafeFileHandle job, int kind, ref Limits limits, uint size);
    [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
    internal static SafeFileHandle Create()
    {
        var handle=CreateJobObject(IntPtr.Zero,null); var limits=new Limits { Basic = new Basic { Flags=0x2000 } };
        if(handle.IsInvalid || !SetInformationJobObject(handle,9,ref limits,(uint)Marshal.SizeOf<Limits>())) { handle.Dispose(); throw new Win32Exception("无法创建后台进程边界。"); }
        return handle;
    }
}
