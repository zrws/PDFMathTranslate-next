using System.Diagnostics;
using System.Net.Http;
using System.Text;

namespace PDFMathTranslateLauncher;

/// <summary>
/// 管理便携 Python 后端进程：环境变量配置、启动、WebUI 就绪探测与退出清理。
/// 逻辑继承自原控制台启动器，行为保持一致。
/// </summary>
internal sealed class BackendRunner : IDisposable
{
    private const int ProxyPort = 11178;
    private static readonly TimeSpan WebUiTimeout = TimeSpan.FromMinutes(3);

    private readonly string _python;
    private readonly string _script;
    private readonly string _sitePackages;
    private readonly string _root;

    private Process? _child;
    private readonly ManualResetEventSlim _webUiReady = new(false);
    private readonly object _startLock = new();

    public int Port { get; }

    public bool WebUiReady => _webUiReady.IsSet;

    public bool HasExited => _child is null || _child.HasExited;

    public int ExitCode => _child?.ExitCode ?? 0;

    public string BaseUrl => $"http://127.0.0.1:{Port}/";

    public BackendRunner(string python, string script, string sitePackages, int port, string root)
    {
        _python = python;
        _script = script;
        _sitePackages = sitePackages;
        _root = root;
        Port = port;
    }

    /// <summary>启动后端并阻塞等待 WebUI 就绪；返回是否成功。可重复调用（自动清理旧进程）。</summary>
    public bool StartAndWaitReady()
    {
        lock (_startLock)
        {
            Stop();
            _webUiReady.Reset();

            var startInfo = new ProcessStartInfo
            {
                FileName = _python,
                WorkingDirectory = _root,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
            };
            startInfo.ArgumentList.Add("-u");
            startInfo.ArgumentList.Add(_script);
            startInfo.ArgumentList.Add("--server-port");
            startInfo.ArgumentList.Add(Port.ToString());

            ConfigureNetworkEnvironment(startInfo);
            ConfigurePythonEnvironment(startInfo);

            _child = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            _child.OutputDataReceived += (_, e) => ForwardLog(e.Data, isError: false);
            _child.ErrorDataReceived += (_, e) => ForwardLog(e.Data, isError: true);
            if (!_child.Start())
            {
                Program.AppendLog("无法启动 PDFMathTranslate 后台进程。");
                return false;
            }
            _child.BeginOutputReadLine();
            _child.BeginErrorReadLine();
            Program.AppendLog($"后台已启动，等待 WebUI：{BaseUrl}");
            return WaitForWebUi(_child);
        }
    }

    private bool WaitForWebUi(Process child)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
        var deadline = DateTime.UtcNow + WebUiTimeout;
        while (DateTime.UtcNow < deadline && !child.HasExited)
        {
            try
            {
                using var response = client.GetAsync(BaseUrl).GetAwaiter().GetResult();
                if (_webUiReady.IsSet && (int)response.StatusCode is >= 200 and < 500)
                {
                    Program.AppendLog($"WebUI 已就绪：{BaseUrl}");
                    return true;
                }
            }
            catch (HttpRequestException) { }
            catch (TaskCanceledException) { }
            Thread.Sleep(1000);
        }
        Program.AppendLog(child.HasExited
            ? $"后台进程已退出（代码 {ExitCode}）。"
            : $"WebUI 在 {WebUiTimeout.TotalMinutes} 分钟内未就绪。");
        return false;
    }

    private void ConfigureNetworkEnvironment(ProcessStartInfo startInfo)
    {
        startInfo.Environment["NO_PROXY"] = "127.0.0.1,localhost,::1";
        startInfo.Environment["no_proxy"] = "127.0.0.1,localhost,::1";
        if (Program.CanConnect("127.0.0.1", ProxyPort))
        {
            var proxy = $"http://127.0.0.1:{ProxyPort}";
            startInfo.Environment["HTTP_PROXY"] = proxy;
            startInfo.Environment["HTTPS_PROXY"] = proxy;
            startInfo.Environment["ALL_PROXY"] = proxy;
            Program.AppendLog($"检测到本地代理 127.0.0.1:{ProxyPort}，已启用。");
        }
        else
        {
            startInfo.Environment.Remove("HTTP_PROXY");
            startInfo.Environment.Remove("HTTPS_PROXY");
            startInfo.Environment.Remove("ALL_PROXY");
            Program.AppendLog("未检测到本地代理，使用系统网络。");
        }
    }

    private void ConfigurePythonEnvironment(ProcessStartInfo startInfo)
    {
        var scripts = Path.Combine(_root, "uv-tools", "pdf2zh-next", "Scripts");
        var path = startInfo.Environment.TryGetValue("PATH", out var existingPath)
            ? existingPath
            : Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        startInfo.Environment["PATH"] = scripts + Path.PathSeparator + _root + Path.PathSeparator + path;
        startInfo.Environment["PYTHONPATH"] = _sitePackages;
        startInfo.Environment["PYTHONUTF8"] = "1";
        startInfo.Environment["PYTHONIOENCODING"] = "utf-8";
    }

    private void ForwardLog(string? line, bool isError)
    {
        if (string.IsNullOrEmpty(line)) return;
        if (line.Contains("WebUI ready:", StringComparison.OrdinalIgnoreCase))
        {
            _webUiReady.Set();
        }
        Program.AppendLog(line);
    }

    public void Dispose()
    {
        lock (_startLock)
        {
            try
            {
                if (_child is { HasExited: false })
                {
                    _child.Kill(entireProcessTree: true);
                    _child.WaitForExit(5000);
                }
            }
            catch { }
            finally
            {
                _child?.Dispose();
                _child = null;
            }
        }
        // 注意：不释放 _webUiReady —— 后台就绪探测线程可能仍在访问它，
        // 进程退出时由运行时统一回收，避免 ObjectDisposedException 竞态。
    }

    private void Stop()
    {
        try
        {
            if (_child is { HasExited: false })
            {
                _child.Kill(entireProcessTree: true);
                _child.WaitForExit(5000);
            }
        }
        catch { }
        finally
        {
            _child?.Dispose();
            _child = null;
        }
    }
}
