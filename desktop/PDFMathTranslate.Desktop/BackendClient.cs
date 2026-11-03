using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace PDFMathTranslate.Desktop;

public sealed class BackendClient : IDisposable
{
    private readonly HttpClient http;
#if DEBUG
    internal Func<string,bool>? SimulateLostResponse {get;set;}
#endif
    public BackendClient(Uri address, string token)
    {
        http = new HttpClient(new SocketsHttpHandler { UseProxy = false }) { BaseAddress = address, Timeout = TimeSpan.FromMinutes(3) };
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }
    public async Task<JsonElement> JsonAsync(string path, HttpMethod? method = null, object? body = null, string? key = null, CancellationToken ct = default)
    {
        using var request = new HttpRequestMessage(method ?? HttpMethod.Get, path);
        if (body != null) request.Content = JsonContent.Create(body);
        if (key != null) request.Headers.Add("Idempotency-Key", key);
        using var response = await http.SendAsync(request, ct);
        var result=await Parse(response,ct);
#if DEBUG
        if(SimulateLostResponse?.Invoke(path)==true)throw new HttpRequestException("本机测试注入：响应在接收确认前丢失");
#endif
        return result;
    }
    private static async Task<JsonElement> Parse(HttpResponseMessage response, CancellationToken ct)
    {
        var text = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
        {
            string error = "服务未完成操作，请检查设置后重试。";
            try { using var doc = JsonDocument.Parse(text); error = doc.RootElement.GetProperty("detail").GetString() ?? error; } catch (JsonException) { }
            throw new InvalidOperationException(error);
        }
        using var json = JsonDocument.Parse(text);
        return json.RootElement.Clone();
    }
    public async Task<ImportedFile> UploadAsync(string path, CancellationToken ct = default)
    {
        await using var stream = File.OpenRead(path);
        using var body = new MultipartFormDataContent();
        body.Add(new StreamContent(stream), "file", Path.GetFileName(path));
        using var response = await http.PostAsync("api/files", body, ct);
        var data = await Parse(response, ct);
        return new ImportedFile(data.GetProperty("file_id").GetString()!, data.GetProperty("filename").GetString()!, data.GetProperty("page_count").GetInt32(), data.GetProperty("size_bytes").GetInt64());
    }
    public async Task<PreviewFrame> PreviewAsync(string path, CancellationToken ct)
    {
        using var response=await http.GetAsync(path,ct);response.EnsureSuccessStatusCode();
        var pages=response.Headers.TryGetValues("X-Page-Count",out var values)&&int.TryParse(values.FirstOrDefault(),out var count)?count:1;
        var index=response.Headers.TryGetValues("X-Page-Index",out values)&&int.TryParse(values.FirstOrDefault(),out var current)?current:1;
        return new PreviewFrame(await response.Content.ReadAsByteArrayAsync(ct),pages,index);
    }
    public async Task<JsonElement> UploadGlossaryAsync(string path)
    {
        await using var stream=File.OpenRead(path); using var body=new MultipartFormDataContent();
        body.Add(new StreamContent(stream),"file",Path.GetFileName(path));
        using var response=await http.PostAsync("api/glossary",body);
        return await Parse(response,CancellationToken.None);
    }
    public async Task EventsAsync(Func<string, JsonElement, Task> receive, Action<string> state, CancellationToken ct)
    {
        string? cursor = null;
        var failures = 0;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, "api/events");
                if (cursor != null) request.Headers.TryAddWithoutValidation("Last-Event-ID", cursor);
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
                response.EnsureSuccessStatusCode();
                await using var stream = await response.Content.ReadAsStreamAsync(ct);
                using var reader = new StreamReader(stream);
                string? line; string type = "", id = ""; var data = new System.Text.StringBuilder();
                state("进度实时同步"); failures = 0;
                while ((line = await reader.ReadLineAsync(ct)) != null)
                {
                    if (line.Length == 0)
                    {
                        if (data.Length > 0)
                        {
                            using var json = JsonDocument.Parse(data.ToString());
                            if (type == "resync") { cursor = null; break; }
                            var envelope = json.RootElement;
                            var expected = $"{envelope.GetProperty("instance_id").GetString()}:{envelope.GetProperty("event_id").GetInt64()}";
                            if (id != expected) throw new InvalidDataException("进度事件身份不匹配");
                            await receive(type, envelope.Clone()); cursor = id;
                        }
                        type = ""; id = ""; data.Clear();
                    }
                    else if (line.StartsWith("id: ")) id = line[4..];
                    else if (line.StartsWith("event: ")) type = line[7..];
                    else if (line.StartsWith("data: ")) data.Append(line[6..]);
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex) when (ex is HttpRequestException or IOException or JsonException or OperationCanceledException)
            { state("连接中断，正在恢复进度快照…"); }
            if (!ct.IsCancellationRequested) await Task.Delay(TimeSpan.FromMilliseconds(Math.Min(30000, 500 * Math.Pow(2, Math.Min(failures++, 6))) + Random.Shared.Next(200)), ct);
        }
    }
    public void Dispose() => http.Dispose();
}
