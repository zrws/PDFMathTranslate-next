using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace PDFMathTranslate.Desktop;

public sealed record UpdatePackage(Version Version,Uri Url,string Sha256,long Size,string Notes);
public sealed class UpdateService
{
    private readonly HttpClient http;
    private readonly bool preview;
    private readonly Uri? testFeed;
    public UpdateService(HttpClient http,bool preview,Uri? testFeed=null)
    {
        if(testFeed!=null && (!testFeed.IsLoopback || testFeed.Scheme!="http")) throw new ArgumentException("测试更新源必须位于本机回环地址。");
        this.http=http;this.preview=preview;this.testFeed=testFeed;
    }
    public async Task<UpdatePackage?> CheckAsync(Version current,CancellationToken ct=default)
    {
        if(preview&&testFeed==null)return null;
        var release=testFeed??new Uri("https://api.github.com/repos/zrws/PDFMathTranslate-next/releases/latest");
        using var info=await ReadJson(release,ct);
        var asset=info.RootElement.GetProperty("assets").EnumerateArray().FirstOrDefault(x=>x.GetProperty("name").GetString()=="latest.json");
        if(asset.ValueKind==JsonValueKind.Undefined)return null;
        var manifest=new Uri(asset.GetProperty("browser_download_url").GetString()!);ValidateUrl(manifest);
        using var doc=await ReadJson(manifest,ct);var data=doc.RootElement;
        if(!Version.TryParse(data.GetProperty("version").GetString(),out var version)||version<=current)return null;
        var url=new Uri(data.GetProperty("url").GetString()!);ValidateUrl(url);
        var sha=data.GetProperty("sha256").GetString()??"";
        if(!Regex.IsMatch(sha,"\\A[0-9a-fA-F]{64}\\z"))throw new InvalidDataException("更新清单缺少有效 SHA256，已拒绝下载。");
        return new UpdatePackage(version,url,sha,data.TryGetProperty("size",out var size)?size.GetInt64():0,data.TryGetProperty("notes",out var notes)?notes.GetString()??"":"");
    }
    private void ValidateUrl(Uri uri)
    {
        if(testFeed!=null){if(!uri.IsLoopback||uri.Scheme!="http")throw new InvalidDataException("测试更新源不得跳转到外网。");}
        else if(uri.Scheme!="https"||uri.UserInfo.Length>0||uri.Host is not ("github.com" or "api.github.com" or "objects.githubusercontent.com" or "release-assets.githubusercontent.com"))throw new InvalidDataException("更新地址不受信任。");
    }
    private async Task<JsonDocument> ReadJson(Uri url,CancellationToken ct)
    {
        using var response=await GetAllowed(url,ct);
        await using var stream=await response.Content.ReadAsStreamAsync(ct);using var buffer=new MemoryStream();
        var bytes=new byte[16384];int count;
        while((count=await stream.ReadAsync(bytes,ct))>0){if(buffer.Length+count>1024*1024)throw new InvalidDataException("更新清单超出大小限制。");buffer.Write(bytes,0,count);}
        return JsonDocument.Parse(buffer.ToArray());
    }
    private async Task<HttpResponseMessage> GetAllowed(Uri url,CancellationToken ct)
    {
        for(var redirects=0;redirects<8;redirects++)
        {
            ValidateUrl(url);
            var response=await http.GetAsync(url,HttpCompletionOption.ResponseHeadersRead,ct);
            if((int)response.StatusCode is >=300 and <400 && response.Headers.Location is { } location)
            {url=new Uri(url,location);response.Dispose();continue;}
            try{if(response.RequestMessage?.RequestUri is {} final)ValidateUrl(final);response.EnsureSuccessStatusCode();return response;}
            catch{response.Dispose();throw;}
        }
        throw new InvalidDataException("更新跳转次数超出限制。");
    }
    public async Task<string> DownloadAsync(UpdatePackage package,string ownedDirectory,Action<long,long>? progress=null,CancellationToken ct=default)
    {
        ValidateUrl(package.Url);
        if(!Regex.IsMatch(package.Sha256,"\\A[0-9a-fA-F]{64}\\z"))throw new InvalidDataException("安装包缺少校验值。");
        Directory.CreateDirectory(ownedDirectory);
        var target=Path.Combine(ownedDirectory,$"PDFMathTranslate-Setup-{package.Version}-{Guid.NewGuid():N}.exe");
        var partial=target+".partial";
        try
        {
            using var response=await GetAllowed(package.Url,ct);
            await using(var input=await response.Content.ReadAsStreamAsync(ct))
            await using(var output=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,FileShare.None,81920,true))
            {
                var buffer=new byte[81920];long done=0;int read;
                while((read=await input.ReadAsync(buffer,ct))>0){done+=read;if(done>2L*1024*1024*1024)throw new InvalidDataException("安装包超出大小限制。");await output.WriteAsync(buffer.AsMemory(0,read),ct);progress?.Invoke(done,response.Content.Headers.ContentLength??package.Size);}
                if(package.Size>0&&done!=package.Size)throw new InvalidDataException("安装包大小不符。");
                await output.FlushAsync(ct);
            }
            // The write handle is closed before the Windows hash read.
            await using(var file=File.OpenRead(partial))
            {
                var hash=Convert.ToHexString(await SHA256.HashDataAsync(file,ct));
                if(!hash.Equals(package.Sha256,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("安装包 SHA256 校验失败，已保留当前版本。");
            }
            File.Move(partial,target);return target;
        }
        finally{if(File.Exists(partial))File.Delete(partial);}
    }
    public static (Version Version,bool Preview) ReadVersion(string root)
    {
        try{using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(root,"version.json")));return(Version.Parse(doc.RootElement.GetProperty("version").GetString()!),!doc.RootElement.TryGetProperty("channel",out var c)||c.GetString()!="stable");}
        catch{return(new Version(2,9,0),true);}
    }
    public static HttpClient CreateClient()
    {
        var handler=new HttpClientHandler{UseProxy=true,AllowAutoRedirect=false};
        if(string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("HTTPS_PROXY"))&&string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("HTTP_PROXY")))
        {
            try{using var probe=new System.Net.Sockets.TcpClient();if(probe.ConnectAsync(IPAddress.Loopback,7897).Wait(150)&&probe.Connected)handler.Proxy=new WebProxy("http://127.0.0.1:7897",true);}catch(System.Net.Sockets.SocketException){}catch(AggregateException){}
        }
        var client=new HttpClient(handler){Timeout=TimeSpan.FromMinutes(15)};
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PDFMathTranslate-Desktop/2.9.0");return client;
    }
    public static void LaunchInstaller(string path)=>Process.Start(new ProcessStartInfo(path){Arguments="/SILENT",UseShellExecute=true});
}
