using System.Collections.ObjectModel;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;

namespace PDFMathTranslate.Desktop;

public static class RuntimePaths
{
    public static string? OptionalEnvironment(string name)
    {var value=Environment.GetEnvironmentVariable(name);return string.IsNullOrWhiteSpace(value)?null:value;}
}

public sealed record Choice(string Code, string Label) { public override string ToString() => Label; }
public static class LanguageChoices
{
    public static Choice? Resolve(ICollection<Choice> choices,string? code)
    {
        if(string.IsNullOrWhiteSpace(code))return null;
        var existing=choices.FirstOrDefault(x=>x.Code.Equals(code,StringComparison.OrdinalIgnoreCase));
        if(existing!=null)return existing;
        string label;try{label=System.Globalization.CultureInfo.GetCultureInfo(code).DisplayName;}catch(System.Globalization.CultureNotFoundException){label=code;}
        var value=new Choice(code,label);choices.Add(value);return value;
    }
}
public sealed record ImportedFile(string Id, string Filename, int Pages, long Bytes);
public sealed record PreviewFrame(byte[] Image,int Pages,int Page);
public sealed record GlossaryRow(string Source,string Target,string File);
public sealed record SavedOutput(string FullPath)
{
    public string Filename => Path.GetFileName(FullPath);
    public string Format => Path.GetExtension(FullPath).Equals(".pdf",StringComparison.OrdinalIgnoreCase)?"PDF 文档":"术语文件";
}
public sealed class TaskRow : ObservableObject
{
    private JsonElement value;
    public TaskRow(JsonElement data) { value = data.Clone(); }
    public string Id => value.GetProperty("id").GetString()!;
    public string Filename => value.GetProperty("filename").GetString() ?? "";
    public string Status => Text("status");
    public string Stage => Text("stage");
    public string Message => Text("message");
    public string Error => Text("error");
    public string Languages => $"{Text("lang_in")} → {Text("lang_out")}";
    public int Revision => value.TryGetProperty("revision", out var p) ? p.GetInt32() : 0;
    public double Progress => value.TryGetProperty("progress", out var p) ? p.GetDouble() : 0;
    public bool Terminal => Status is "done" or "failed" or "cancelled";
    public string StatusLabel => Status switch { "queued" => "等待中", "running" => "翻译中", "done" => "翻译完成", "failed" => "失败", "cancelled" => "已取消", _ => Status };
    public string SavedPaths => value.TryGetProperty("saved_paths", out var paths) ? string.Join(Environment.NewLine, paths.EnumerateArray().Select(x => x.GetString())) : "";
    public IReadOnlyList<SavedOutput> SavedFiles => SavedPaths.Split(Environment.NewLine,StringSplitOptions.RemoveEmptyEntries).Select(x=>new SavedOutput(x)).ToArray();
    public string PlannedDirectory => value.TryGetProperty("options",out var options)&&options.TryGetProperty("export_dir",out var dir)?dir.GetString()??"":"";
    public string Detail => $"{Filename}　{Languages}\n{Stage} · {Message}\n{Error}\n{SavedPaths}".Trim();
    public IEnumerable<string> Kinds => value.TryGetProperty("outputs", out var outputs) ? outputs.EnumerateObject().Select(x => x.Name).ToArray() : [];
    private string Text(string key) => value.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() ?? "" : "";
    public void Update(JsonElement data)
    {
        if (data.TryGetProperty("revision", out var revision) && revision.GetInt32() <= Revision) return;
        if (Terminal && data.GetProperty("status").GetString() is "queued" or "running") return;
        value = data.Clone(); OnPropertyChanged(string.Empty);
    }
}

// One instance, bound by every page. All mutations are dispatched onto the UI thread.
public sealed class TaskStore : ObservableObject
{
    public ObservableCollection<TaskRow> Tasks { get; } = [];
    private readonly Dictionary<string, TaskRow> index = [];
    public string? InstanceId { get; private set; }
    public long Watermark { get; private set; } = -1;
    public string? HistoryCursor { get; private set; }
    public string Summary => $"{Tasks.Count(x => !x.Terminal)} 项进行中 · {Tasks.Count(x => x.Terminal)} 项历史";
    public void Apply(string eventType, JsonElement envelope)
    {
        var instance = envelope.GetProperty("instance_id").GetString()!;
        var seq = envelope.GetProperty("event_id").GetInt64();
        if (eventType == "snapshot")
        {
            if (InstanceId == instance && seq < Watermark) return;
            var previous=InstanceId==instance?new Dictionary<string,TaskRow>(index):[];
            Tasks.Clear(); index.Clear(); InstanceId = instance; Watermark = seq;
            var data = envelope.GetProperty("data");
            foreach (var task in data.GetProperty("tasks").EnumerateArray())
            {
                var id=task.GetProperty("id").GetString()!;
                if(previous.TryGetValue(id,out var row)){row.Update(task);index.Add(id,row);Tasks.Add(row);}
                else Merge(task);
            }
            HistoryCursor = data.TryGetProperty("next_cursor", out var c) ? c.GetString() : null;
        }
        else
        {
            if (instance != InstanceId || seq <= Watermark) return;
            Watermark = seq;
            if (eventType.StartsWith("task.", StringComparison.Ordinal)) Merge(envelope.GetProperty("data"));
        }
        OnPropertyChanged(nameof(Summary));
    }
    public void Merge(JsonElement data)
    {
        var id = data.GetProperty("id").GetString()!;
        if (index.TryGetValue(id, out var current)) current.Update(data);
        else { var row = new TaskRow(data); index.Add(id, row); Tasks.Insert(0, row); }
        OnPropertyChanged(nameof(Summary));
    }
    public void AddHistory(JsonElement page)
    {
        foreach (var task in page.GetProperty("history").EnumerateArray()) Merge(task);
        HistoryCursor = page.TryGetProperty("next_cursor", out var c) ? c.GetString() : null;
    }
}
