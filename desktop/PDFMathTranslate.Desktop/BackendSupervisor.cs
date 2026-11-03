using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace PDFMathTranslate.Desktop;

public sealed class BackendSupervisor : IDisposable
{
    private Process? child;
    private SafeFileHandle? job;
    private readonly SemaphoreSlim startup=new(1,1);
    public BackendClient? Client { get; private set; }
    public string Home { get; private set; } = "";
    internal int ProcessId=>child?.Id??0;
    public async Task<BackendClient> StartAsync(CancellationToken ct)
    {
        await startup.WaitAsync(ct);
        try{return await StartCoreAsync(ct);}
        catch{Dispose();throw;}
        finally{startup.Release();}
    }
    private async Task<BackendClient> StartCoreAsync(CancellationToken ct)
    {
        Dispose();
        var root = Environment.GetEnvironmentVariable("PDF2ZH_APP_ROOT") ?? AppContext.BaseDirectory;
        var runtime = Environment.GetEnvironmentVariable("PDF2ZH_RUNTIME_ROOT") ?? root;
        Home = Environment.GetEnvironmentVariable("PDF2ZH_HOME") ?? (File.Exists(Path.Combine(root, "portable.marker"))
            ? Path.Combine(root, "home") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PDFMathTranslate"));
        Home = Path.GetFullPath(Home);
        Directory.CreateDirectory(Home);
        var candidates = Directory.Exists(Path.Combine(runtime, "uv-python")) ? Directory.GetDirectories(Path.Combine(runtime, "uv-python")) : [];
        var python = candidates.Where(x => Version.TryParse(Path.GetFileName(x).Split('-').ElementAtOrDefault(1), out var v) && v.Build >= 0)
            .OrderByDescending(x => Version.Parse(Path.GetFileName(x).Split('-')[1])).Select(x => Path.Combine(x, "python.exe")).FirstOrDefault(File.Exists);
        var packages = Path.Combine(runtime, "uv-tools", "pdf2zh-next", "Lib", "site-packages");
        if (python == null || !Directory.Exists(packages)) throw new InvalidOperationException("运行环境缺失。请使用完整安装包重新安装，已有文档与设置会保留。");
        var work = Path.Combine(Home, "work"); Directory.CreateDirectory(work);
        var info = new ProcessStartInfo(python) { WorkingDirectory = work, UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        info.ArgumentList.Add("-u"); info.ArgumentList.Add("-m"); info.ArgumentList.Add("pdf2zh_next.desktop.server");
        var source = Environment.GetEnvironmentVariable("PDF2ZH_SOURCE_ROOT");
        info.Environment["PYTHONPATH"] = source == null ? packages : source + Path.PathSeparator + packages;
        foreach (var key in info.Environment.Keys.Where(x => x.StartsWith("PDF2ZH_", StringComparison.OrdinalIgnoreCase) || x.StartsWith("BABELDOC_", StringComparison.OrdinalIgnoreCase)).ToArray()) info.Environment.Remove(key);
        info.Environment["PDF2ZH_HOME"] = Home;
        info.Environment["PDF2ZH_LEGACY_ROOT"] = root;
        info.Environment["PYTHONNOUSERSITE"] = "1";
        info.Environment["PYTHONDONTWRITEBYTECODE"] = "1";
        info.Environment["PYTHONUTF8"] = "1";
        info.Environment["NO_PROXY"] = "127.0.0.1,localhost,::1";
        info.Environment["BABELDOC_ASSETS_UPSTREAM"] = "modelscope";
        if (info.Environment.TryGetValue("SSL_CERT_DIR",out var certDir) && !Directory.Exists(certDir)) info.Environment.Remove("SSL_CERT_DIR");
        if (info.Environment.TryGetValue("SSL_CERT_FILE",out var certFile) && !File.Exists(certFile)) info.Environment.Remove("SSL_CERT_FILE");
        foreach (var (key, path) in new Dictionary<string,string> { ["HOME"]=Home, ["USERPROFILE"]=Home, ["APPDATA"]=Path.Combine(Home,"AppData","Roaming"), ["LOCALAPPDATA"]=Path.Combine(Home,"AppData","Local"), ["TEMP"]=Path.Combine(Home,"tmp"), ["TMP"]=Path.Combine(Home,"tmp"), ["XDG_CACHE_HOME"]=Path.Combine(Home,".cache") }) { Directory.CreateDirectory(path); info.Environment[key]=path; }
        info.Environment["PDF2ZH_CONFIG_FILE"] = Path.Combine(Home, ".config", "pdf2zh", "config.v3.toml");
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        job = NativeJob.Create();
        child = Process.Start(info) ?? throw new InvalidOperationException("无法启动翻译服务，请检查安装目录。");
        if (!NativeJob.AssignProcessToJobObject(job, child.Handle)) { child.Kill(true); throw new Win32Exception("无法建立后台进程回收边界。"); }
        // Never put the token in argv, environment, logs, or a URL.
        await child.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { token, downloads = DownloadsDirectory() }));
        await child.StandardInput.FlushAsync(ct);
        child.ErrorDataReceived += (_, _) => { }; child.BeginErrorReadLine();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct); deadline.CancelAfter(TimeSpan.FromSeconds(45));
        var line = await child.StandardOutput.ReadLineAsync(deadline.Token);
        if (line == null) throw new InvalidOperationException("翻译服务未能启动。数据目录可能已被另一入口占用，请关闭后重试。");
        using var hello = JsonDocument.Parse(line);
        var port = hello.RootElement.GetProperty("port").GetInt32();
        if (port is < 1 or > 65535 || hello.RootElement.GetProperty("pid").GetInt32() != child.Id) throw new InvalidDataException("后台实例身份不匹配。");
        _ = child.StandardOutput.ReadToEndAsync(ct);
        Client = new BackendClient(new Uri($"http://127.0.0.1:{port}/"), token);
        while (!deadline.IsCancellationRequested)
        {
            try { var health = await Client.JsonAsync("api/health", ct: deadline.Token); if (health.GetProperty("control_ready").GetBoolean()) return Client; }
            catch (System.Net.Http.HttpRequestException) { }
            if (child.HasExited) throw new InvalidOperationException("翻译服务已退出，请重试启动。");
            await Task.Delay(150, deadline.Token);
        }
        throw new InvalidOperationException("翻译服务启动超时，请重试。");
    }
    private static string DownloadsDirectory()
    {
        var id = new Guid("374DE290-123F-4565-9164-39C4925E467B");
        if (SHGetKnownFolderPath(ref id, 0, IntPtr.Zero, out var ptr) != 0) return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        try { return Marshal.PtrToStringUni(ptr)!; } finally { Marshal.FreeCoTaskMem(ptr); }
    }
    [DllImport("shell32.dll")] private static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
    public void Dispose()
    {
        Client?.Dispose(); Client = null;
        job?.Dispose(); job = null; // KILL_ON_JOB_CLOSE includes nested translation/render workers.
        try { if (child is { HasExited: false }) { child.Kill(true); child.WaitForExit(3000); } } catch (InvalidOperationException) { }
        child?.Dispose(); child = null;
    }
}

