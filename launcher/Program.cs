using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;

namespace PDFMathTranslateLauncher;

/// <summary>应用入口：定位便携运行环境、选择端口，然后显示 WebView2 主窗口。</summary>
internal static class Program
{
    public const int DefaultPort = 7860;

    private static Mutex? _singleInstanceMutex;

    public static string Root { get; } =
        AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);

    public static string LogPath { get; } = Path.Combine(Root, "logs", "webui-launcher.log");

    [STAThread]
    private static int Main(string[] args)
    {
        Directory.CreateDirectory(Path.Combine(Root, "logs"));
        AppendLog($"启动请求：{DateTime.Now:yyyy-MM-dd HH:mm:ss}");

        // 单实例：避免重复启动两个后台 Python 进程。
        _singleInstanceMutex = new Mutex(true, @"Global\PDFMathTranslateNextSingleInstance", out var createdNew);
        if (!createdNew)
        {
            MessageBox.Show("PDFMathTranslate 已经在运行中。", "PDFMathTranslate",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }

        var python = FindPortablePython(Root);
        var script = ResolveEntryScript(args);
        var sitePackages = Path.Combine(Root, "uv-tools", "pdf2zh-next", "Lib", "site-packages");
        if (python is null || !File.Exists(script) || !Directory.Exists(sitePackages))
        {
            ShowFatal("找不到便携运行环境。请通过安装程序重新安装 PDFMathTranslate。\n" +
                      $"需要 Python：{python ?? "uv-python\\*\\python.exe"}\n" +
                      $"需要文件：{script}\n需要目录：{sitePackages}");
            return 2;
        }

        var port = ReadPort(args);
        if (port == 0)
        {
            port = FindFreePort(DefaultPort);
        }
        else if (!IsPortFree(port))
        {
            AppendLog($"端口 {port} 已被占用，正在寻找可用端口...");
            port = FindFreePort(port + 1);
        }
        AppendLog($"使用端口：{port}");

        ApplicationConfiguration.Initialize();

        using var backend = new BackendRunner(python, script, sitePackages, port, Root);
        using var form = new MainForm(backend, port);
        Application.Run(form);
        return 0;
    }

    public static string ConfigDirectory => Path.Combine(Root, "home", ".config", "pdf2zh");

    public static void OpenInExplorer(string directory)
    {
        if (Directory.Exists(directory))
        {
            Process.Start(new ProcessStartInfo { FileName = directory, UseShellExecute = true });
        }
    }

    public static void OpenUrlInSystemBrowser(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            AppendLog("无法打开链接：" + ex.Message);
        }
    }

    public static void ShowFatal(string message)
    {
        AppendLog(message);
        MessageBox.Show(message, "PDFMathTranslate", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    /// <summary>选择启动入口：默认新界面（start-webui.py），--legacy-gui 走 Gradio 旧界面。</summary>
    private static string ResolveEntryScript(string[] args)
    {
        var modern = Path.Combine(Root, "start-webui.py");
        var classic = Path.Combine(Root, "start-gui-direct.py");
        if (args.Any(a => string.Equals(a, "--legacy-gui", StringComparison.OrdinalIgnoreCase)))
        {
            return classic;
        }
        return File.Exists(modern) ? modern : classic;
    }
    private static string? FindPortablePython(string root)
    {
        var embeddedRoot = Path.Combine(root, "uv-python");
        var embeddedPython = Directory.Exists(embeddedRoot)
            ? Directory.GetFiles(embeddedRoot, "python.exe", SearchOption.AllDirectories).FirstOrDefault()
            : null;
        if (embeddedPython is not null) return embeddedPython;

        var venvPython = Path.Combine(root, "uv-tools", "pdf2zh-next", "Scripts", "python.exe");
        return File.Exists(venvPython) ? venvPython : null;
    }

    private static int ReadPort(string[] args)
    {
        for (var i = 0; i < args.Length; i++)
        {
            if ((args[i] is "--server-port" or "--port") && i + 1 < args.Length &&
                int.TryParse(args[i + 1], out var port) && port is > 0 and <= 65535)
            {
                return port;
            }
        }
        return 0;
    }

    private static int FindFreePort(int preferred)
    {
        for (var port = preferred; port <= 65535; port++)
        {
            if (IsPortFree(port)) return port;
        }
        throw new InvalidOperationException("没有可用 TCP 端口。");
    }

    private static bool IsPortFree(int port)
    {
        try
        {
            using var listener = new TcpListener(IPAddress.Loopback, port);
            listener.Start();
            listener.Stop();
            return true;
        }
        catch (SocketException) { return false; }
    }

    public static bool CanConnect(string host, int port)
    {
        try
        {
            using var client = new TcpClient();
            var task = client.ConnectAsync(host, port);
            return task.Wait(TimeSpan.FromMilliseconds(250)) && client.Connected;
        }
        catch (SocketException) { return false; }
    }

    public static void AppendLog(string? message)
    {
        if (string.IsNullOrEmpty(message)) return;
        try
        {
            File.AppendAllText(LogPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {RedactSensitive(message)}{Environment.NewLine}");
        }
        catch { }
    }

    public static string RedactSensitive(string message)
    {
        var redacted = Regex.Replace(message, @"(?i)sk-[A-Za-z0-9_-]{16,}", "sk-<redacted>");
        redacted = Regex.Replace(
            redacted,
            @"(?i)(api[_-]?key|authorization|token|password)\s*[:=]\s*([^\s,;]+)",
            "$1=<redacted>");
        return redacted;
    }
}
