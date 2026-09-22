using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace PDFMathTranslateLauncher;

/// <summary>一次可用的更新描述（来自 Releases 的 latest.json）。</summary>
internal sealed record UpdateInfo(Version Version, string Url, string Sha256, string Notes, long Size);

/// <summary>
/// 自动更新：读取 GitHub Releases 的 latest.json 清单，比较版本、
/// 下载安装器并校验 SHA256，然后以 /SILENT 静默重装（整包替换）。
/// 所有网络失败均静默返回 null，不阻塞正常使用。
/// </summary>
internal static class UpdateChecker
{
    private const string Repo = "zrws/PDFMathTranslate-next";
    private const int LocalProxyPort = 11178;

    /// <summary>从安装目录读取当前版本（version.json）；缺失返回 null。</summary>
    public static Version? ReadCurrentVersion(string root)
    {
        try
        {
            var path = Path.Combine(root, "version.json");
            if (!File.Exists(path)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            return Version.Parse(doc.RootElement.GetProperty("version").GetString()
                ?? throw new InvalidOperationException("version.json 缺少 version 字段"));
        }
        catch
        {
            return null;
        }
    }

    /// <summary>检查更新；无更新或网络失败返回 null。</summary>
    public static async Task<UpdateInfo?> CheckAsync(Version current)
    {
        try
        {
            using var client = CreateHttpClient(TimeSpan.FromSeconds(15));
            using var releaseResponse = await client.GetAsync($"https://api.github.com/repos/{Repo}/releases/latest");
            releaseResponse.EnsureSuccessStatusCode();
            using var releaseDoc = JsonDocument.Parse(await releaseResponse.Content.ReadAsStringAsync());

            string? manifestUrl = null;
            foreach (var asset in releaseDoc.RootElement.GetProperty("assets").EnumerateArray())
            {
                if (asset.GetProperty("name").GetString() == "latest.json")
                {
                    manifestUrl = asset.GetProperty("browser_download_url").GetString();
                    break;
                }
            }
            if (manifestUrl is null) return null;

            using var manifestResponse = await client.GetAsync(manifestUrl);
            manifestResponse.EnsureSuccessStatusCode();
            using var manifestDoc = JsonDocument.Parse(await manifestResponse.Content.ReadAsStringAsync());
            var root = manifestDoc.RootElement;

            var version = Version.Parse(root.GetProperty("version").GetString()!);
            if (version <= current) return null;

            var url = root.GetProperty("url").GetString()!;
            var sha256 = root.TryGetProperty("sha256", out var sha) ? sha.GetString() ?? "" : "";
            var notes = root.TryGetProperty("notes", out var noteEl) ? noteEl.GetString() ?? "" : "";
            var size = root.TryGetProperty("size", out var sizeEl) ? sizeEl.GetInt64() : 0;
            return new UpdateInfo(version, url, sha256, notes, size);
        }
        catch (Exception ex)
        {
            Program.AppendLog("检查更新失败（已忽略）：" + ex.Message);
            return null;
        }
    }

    /// <summary>下载安装器到临时目录并校验 SHA256；失败抛异常。</summary>
    public static async Task<string> DownloadAsync(
        UpdateInfo info,
        Action<long, long> progress,
        CancellationToken cancellationToken)
    {
        var targetPath = Path.Combine(
            Path.GetTempPath(),
            $"PDFMathTranslate-Setup-{info.Version}.exe");

        using var client = CreateHttpClient(TimeSpan.FromMinutes(20));
        using var response = await client.GetAsync(info.Url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();

        var total = response.Content.Headers.ContentLength ?? info.Size;
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var target = File.Create(targetPath);

        var buffer = new byte[81920];
        long read = 0;
        int chunk;
        while ((chunk = await source.ReadAsync(buffer, cancellationToken)) > 0)
        {
            await target.WriteAsync(buffer.AsMemory(0, chunk), cancellationToken);
            read += chunk;
            progress(read, total);
        }

        if (!string.IsNullOrEmpty(info.Sha256) && !await VerifySha256Async(targetPath, info.Sha256))
        {
            throw new InvalidOperationException("安装包 SHA256 校验未通过。");
        }
        return targetPath;
    }

    /// <summary>以 /SILENT 启动安装器（显示进度但不提问），由调用方随后退出应用。</summary>
    public static void LaunchInstaller(string installerPath)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = installerPath,
            Arguments = "/SILENT",
            UseShellExecute = true,
        });
    }

    private static async Task<bool> VerifySha256Async(string path, string expectedHex)
    {
        using var sha = SHA256.Create();
        await using var stream = File.OpenRead(path);
        var hash = await sha.ComputeHashAsync(stream);
        var actual = Convert.ToHexString(hash).ToLowerInvariant();
        return string.Equals(actual, expectedHex.Trim().ToLowerInvariant(), StringComparison.Ordinal);
    }

    private static HttpClient CreateHttpClient(TimeSpan timeout)
    {
        HttpClientHandler handler = new();
        if (Program.CanConnect("127.0.0.1", LocalProxyPort))
        {
            // 与启动器一致：本地代理优先（系统代理作为 HttpClient 默认行为仍然生效）。
            handler.Proxy = new System.Net.WebProxy($"http://127.0.0.1:{LocalProxyPort}", BypassOnLocal: true);
            handler.UseProxy = true;
        }
        var client = new HttpClient(handler) { Timeout = timeout };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PDFMathTranslate-Updater/1.0");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }
}
