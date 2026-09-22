using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2;
using Microsoft.Web.WebView2.WinForms;

namespace PDFMathTranslateLauncher;

/// <summary>WebView2 桌面壳主窗口：启动页 → 等待后端就绪 → 内嵌 WebUI。</summary>
internal sealed class MainForm : Form
{
    private const string RepoUrl = "https://github.com/zrws/PDFMathTranslate-next";
    private const int AutoUpdateCheckDelayMs = 8000;

    private readonly BackendRunner _backend;
    private readonly WebView2 _webView = new();
    private readonly ToolStripMenuItem _checkUpdateMenuItem;
    private bool _webUiShown;
    private bool _updateInProgress;
    private CancellationTokenSource? _updateCts;

    public MainForm(BackendRunner backend, int port)
    {
        _backend = backend;

        Text = "PDFMathTranslate";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(1280, 800);
        MinimumSize = new Size(960, 640);
        Icon = TryLoadIcon();
        Font = new Font("Segoe UI", 9F);

        // 菜单栏：文件 / 帮助
        var fileMenu = new ToolStripMenuItem("文件(&F)");
        fileMenu.DropDownItems.Add("打开日志目录", null, (_, _) => Program.OpenInExplorer(Path.Combine(Program.Root, "logs")));
        fileMenu.DropDownItems.Add("打开配置目录", null, (_, _) => Program.OpenInExplorer(Program.ConfigDirectory));
        fileMenu.DropDownItems.Add(new ToolStripSeparator());
        fileMenu.DropDownItems.Add("退出", null, (_, _) => Close());

        var helpMenu = new ToolStripMenuItem("帮助(&H)");
        _checkUpdateMenuItem = new ToolStripMenuItem("检查更新", null, async (_, _) => await CheckAndPromptAsync(manual: true));
        helpMenu.DropDownItems.Add(_checkUpdateMenuItem);
        helpMenu.DropDownItems.Add("关于 PDFMathTranslate", null, (_, _) => ShowAbout());

        var menu = new MenuStrip { Items = { fileMenu, helpMenu } };

        _webView.Dock = DockStyle.Fill;
        _webView.CreationProperties = new CoreWebView2CreationProperties
        {
            UserDataFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PDFMathTranslate", "WebView2"),
        };

        Controls.Add(_webView);
        Controls.Add(menu);
        MainMenuStrip = menu;
    }

    protected override async void OnShown(EventArgs e)
    {
        base.OnShown(e);
        try
        {
            await _webView.EnsureCoreWebView2Async();
            HookCoreWebView2();
            ShowSplash();
            _ = RunBackendAsync();
        }
        catch (Exception ex)
        {
            Program.AppendLog("WebView2 初始化失败：" + ex);
            var choice = MessageBox.Show(
                "未检测到 Microsoft WebView2 运行时，无法显示界面。\n\n" +
                "是否现在打开下载页面安装 WebView2？（安装后重新启动本程序即可）",
                "PDFMathTranslate", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (choice == DialogResult.Yes)
            {
                Program.OpenUrlInSystemBrowser("https://aka.ms/webview2");
            }
            Close();
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        _updateCts?.Cancel();
        _backend.Dispose();
        base.OnFormClosing(e);
    }

    private void HookCoreWebView2()
    {
        var core = _webView.CoreWebView2;
        if (core is null) return;

        // 桌面应用观感：关闭浏览器痕迹（右键菜单 / 开发者工具 / 缩放 / 浏览器快捷键 / 状态栏）
        var webSettings = core.Settings;
        webSettings.AreDefaultContextMenusEnabled = false;
        webSettings.AreDevToolsEnabled = false;
        webSettings.IsStatusBarEnabled = false;
        webSettings.IsZoomControlEnabled = false;
        webSettings.AreBrowserAcceleratorKeysEnabled = false;
        webSettings.IsSwipeNavigationEnabled = false;
        webSettings.IsPasswordAutosaveEnabled = false;
        webSettings.IsGeneralAutofillEnabled = false;
        webSettings.IsPinchZoomEnabled = false;

        // 下载：静默保存到「下载」目录，不显示浏览器式下载提示
        core.DownloadStarting += (_, e) =>
        {
            try
            {
                var downloads = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                Directory.CreateDirectory(downloads);
                var name = Path.GetFileName(e.ResultFilePath);
                var target = Path.Combine(downloads, name);
                var index = 1;
                while (File.Exists(target))
                {
                    var stem = Path.GetFileNameWithoutExtension(name);
                    var ext = Path.GetExtension(name);
                    target = Path.Combine(downloads, $"{stem} ({index++}){ext}");
                }
                e.ResultFilePath = target;
            }
            catch
            {
                // 保底：交给 WebView2 默认行为
            }
            e.Handled = true;
        };

        // 同源导航留在壳内，外链交给系统浏览器。
        core.NavigationStarting += (_, e) =>
        {
            if (IsInternalUri(e.Uri)) return;
            e.Cancel = true;
            Program.OpenUrlInSystemBrowser(e.Uri);
        };
        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            Program.OpenUrlInSystemBrowser(e.Uri);
        };
        // 启动页/错误页按钮 → postMessage
        core.WebMessageReceived += (_, e) =>
        {
            string message;
            try
            {
                message = e.TryGetWebMessageAsString();
            }
            catch (Exception)
            {
                return; // 非 JSON/字符串消息（如结构化数据），忽略
            }
            switch (message)
            {
                case "retry":
                    _ = RunBackendAsync();
                    break;
                case "openlogs":
                    Program.OpenInExplorer(Path.Combine(Program.Root, "logs"));
                    break;
                case "openconfig":
                    Program.OpenInExplorer(Program.ConfigDirectory);
                    break;
            }
        };
    }

    private bool IsInternalUri(string uri)
    {
        if (uri.StartsWith($"{_backend.BaseUrl}", StringComparison.OrdinalIgnoreCase) ||
            uri.Equals($"http://127.0.0.1:{_backend.Port}", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        return uri.StartsWith("about:", StringComparison.OrdinalIgnoreCase) ||
               uri.StartsWith("data:", StringComparison.OrdinalIgnoreCase) ||
               uri.StartsWith("blob:", StringComparison.OrdinalIgnoreCase);
    }

    private async Task RunBackendAsync()
    {
        // 本方法总在 UI 线程发起（OnShown 或错误页重试），await 后续自动回到 UI 线程。
        if (_webUiShown) return;
        ShowSplash();
        _webUiShown = true;

        var ok = await Task.Run(() => _backend.StartAndWaitReady());
        if (IsDisposed) return;
        if (ok)
        {
            _webView.CoreWebView2?.Navigate(_backend.BaseUrl);
            _ = ScheduleAutoUpdateCheckAsync();
        }
        else
        {
            _webUiShown = false;
            ShowErrorPage();
        }
    }

    private void ShowSplash()
    {
        _webView.CoreWebView2?.NavigateToString(SplashHtml);
    }

    private void ShowErrorPage()
    {
        _webView.CoreWebView2?.NavigateToString(ErrorHtml);
    }

    /// <summary>读取界面偏好（webui 写入的 ui-prefs.json）决定是否自动检查更新。</summary>
    private static bool AutoUpdateEnabled()
    {
        try
        {
            // 便携模式在安装目录下，Program Files 安装时数据落在用户目录
            var candidates = new[]
            {
                Path.Combine(Program.Root, "home", ".config", "pdf2zh", "ui-prefs.json"),
                Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "PDFMathTranslate", ".config", "pdf2zh", "ui-prefs.json"),
            };
            foreach (var path in candidates)
            {
                if (!File.Exists(path)) continue;
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                if (doc.RootElement.TryGetProperty("auto_update", out var value) &&
                    value.ValueKind == JsonValueKind.False)
                {
                    Program.AppendLog($"界面偏好（{path}）：已关闭启动时自动检查更新。");
                    return false;
                }
            }
        }
        catch
        {
            // 读取失败时保持默认（自动检查）
        }
        return true;
    }

    private async Task ScheduleAutoUpdateCheckAsync()
    {
        if (_updateInProgress) return;
        if (!AutoUpdateEnabled()) return;
        try
        {
            await Task.Delay(AutoUpdateCheckDelayMs);
        }
        catch (TaskCanceledException) { return; }
        await CheckAndPromptAsync(manual: false);
    }

    private async Task CheckAndPromptAsync(bool manual)
    {
        if (_updateInProgress)
        {
            if (manual) MessageBox.Show("正在检查或下载更新，请稍候。", "PDFMathTranslate",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        var current = UpdateChecker.ReadCurrentVersion(Program.Root);
        if (current is null)
        {
            if (manual)
            {
                MessageBox.Show("未找到版本信息（version.json 缺失），无法检查更新。\n" +
                    $"可前往 GitHub Releases 手动查看：{RepoUrl}/releases",
                    "PDFMathTranslate", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            return;
        }

        _updateInProgress = true;
        _checkUpdateMenuItem.Enabled = false;
        try
        {
            var info = await UpdateChecker.CheckAsync(current);
            if (info is null)
            {
                if (manual)
                {
                    MessageBox.Show("已是最新版本。", "PDFMathTranslate",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                return;
            }

            var message = $"发现新版本 {info.Version}\n\n{info.Notes}\n\n是否现在下载并安装更新？";
            if (MessageBox.Show(message, "发现新版本", MessageBoxButtons.YesNo, MessageBoxIcon.Information)
                != DialogResult.Yes)
            {
                return;
            }

            var path = await DownloadWithProgressAsync(info);
            if (path is null)
            {
                MessageBox.Show("下载失败或校验未通过，请稍后重试，" +
                    $"或前往 GitHub Releases 手动下载：\n{RepoUrl}/releases",
                    "更新失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (MessageBox.Show("下载完成。点击“确定”将关闭应用并开始安装，安装完成后可重新打开。",
                    "准备安装", MessageBoxButtons.OKCancel, MessageBoxIcon.Information)
                == DialogResult.OK)
            {
                UpdateChecker.LaunchInstaller(path);
                Close();
            }
        }
        finally
        {
            _updateInProgress = false;
            if (_checkUpdateMenuItem is not null && !_checkUpdateMenuItem.IsDisposed)
            {
                _checkUpdateMenuItem.Enabled = true;
            }
        }
    }

    private async Task<string?> DownloadWithProgressAsync(UpdateInfo info)
    {
        _updateCts = new CancellationTokenSource();
        using var progressForm = new Form
        {
            Text = "正在下载更新",
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            StartPosition = FormStartPosition.CenterParent,
            ClientSize = new Size(420, 110),
        };
        var label = new Label
        {
            Dock = DockStyle.Top,
            Height = 36,
            TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(12, 8, 12, 0),
            Text = $"正在下载 v{info.Version} …",
        };
        var bar = new ProgressBar { Dock = DockStyle.Bottom, Minimum = 0, Maximum = 100 };
        progressForm.Controls.Add(label);
        progressForm.Controls.Add(bar);
        progressForm.Show(this);

        try
        {
            var path = await UpdateChecker.DownloadAsync(
                info,
                (read, total) =>
                {
                    if (progressForm.IsHandleCreated)
                    {
                        progressForm.BeginInvoke(new Action(() =>
                        {
                            label.Text = $"正在下载 v{info.Version} …  {read / 1048576} MB / {(total > 0 ? total / 1048576 : 0)} MB";
                            bar.Value = total > 0 ? (int)(100L * read / total) : 0;
                        }));
                    }
                },
                _updateCts.Token);
            return path;
        }
        catch (Exception ex)
        {
            Program.AppendLog("更新下载失败：" + ex.Message);
            return null;
        }
        finally
        {
            progressForm.Close();
        }
    }

    private void ShowAbout()
    {
        var version = UpdateChecker.ReadCurrentVersion(Program.Root);
        MessageBox.Show(
            "PDF scientific paper translation and bilingual comparison.\n\n" +
            $"版本：{version?.ToString() ?? "开发版"}\n" +
            $"项目主页：{RepoUrl}\n" +
            "翻译引擎：BabelDOC",
            "关于 PDFMathTranslate", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static Icon? TryLoadIcon()
    {
        try
        {
            var exePath = Environment.ProcessPath;
            if (exePath is not null && File.Exists(exePath))
            {
                return Icon.ExtractAssociatedIcon(exePath);
            }
        }
        catch { }
        return null;
    }

    private const string SplashHtml = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <style>
          body{margin:0;height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;
               background:#F1F5F9;font-family:"Segoe UI","Microsoft YaHei UI",sans-serif;color:#0F172A}
          .logo{width:72px;height:72px;border-radius:18px;background:#0F172A;color:#ffffff;
                font-size:38px;font-weight:600;display:flex;align-items:center;justify-content:center;margin-bottom:24px}
          h1{font-size:20px;margin:0 0 8px}
          p{color:#64748B;font-size:14px;margin:0 0 28px}
          .spinner{width:28px;height:28px;border-radius:50%;border:3px solid #E2E8F0;
                   border-top-color:#0F172A;animation:spin 0.9s linear infinite}
          @keyframes spin{to{transform:rotate(360deg)}}
        </style>
        </head>
        <body>
          <div class="logo">译</div>
          <h1>PDFMathTranslate</h1>
          <p>正在启动翻译引擎，首次启动可能需要 1–3 分钟…</p>
          <div class="spinner"></div>
        </body>
        </html>
        """;

    private const string ErrorHtml = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <style>
          body{margin:0;height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;
               background:#F1F5F9;font-family:"Segoe UI","Microsoft YaHei UI",sans-serif;color:#0F172A}
          .card{background:#ffffff;border:1px solid #E2E8F0;border-radius:12px;padding:28px 32px;
                max-width:460px;text-align:center;box-shadow:0 1px 2px rgba(15,23,42,0.06)}
          h1{font-size:18px;margin:0 0 10px}
          p{color:#64748B;font-size:14px;line-height:1.6;margin:0 0 22px}
          .row{display:flex;gap:12px;justify-content:center}
          button{border:1px solid #E2E8F0;background:#ffffff;color:#0F172A;border-radius:8px;
                 padding:9px 18px;font-size:14px;cursor:pointer}
          button.primary{background:#0F172A;border-color:#0F172A;color:#ffffff}
          button:hover{opacity:0.88}
        </style>
        </head>
        <body>
          <div class="card">
            <h1>翻译引擎未能启动</h1>
            <p>后端进程启动失败或超时未就绪。<br>可查看日志排查原因，或重试一次。</p>
            <div class="row">
              <button class="primary" onclick="window.chrome.webview.postMessage('retry')">重试</button>
              <button onclick="window.chrome.webview.postMessage('openlogs')">打开日志</button>
            </div>
          </div>
        </body>
        </html>
        """;
}
