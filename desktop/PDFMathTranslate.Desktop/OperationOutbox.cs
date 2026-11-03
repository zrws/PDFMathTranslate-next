using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PDFMathTranslate.Desktop;

public sealed record PendingOperation(string Identity,string Key,string Kind,string Endpoint,JsonElement Payload);
public sealed class OperationOutbox
{
    private readonly string path;
    private readonly Dictionary<string,PendingOperation> pending;
    public OperationOutbox(string home)
    {
        path=Path.Combine(home,"ui","operation-outbox.json");
        pending=File.Exists(path)?JsonSerializer.Deserialize<Dictionary<string,PendingOperation>>(File.ReadAllText(path))??[]:[];
        if(pending.Count>128)throw new InvalidDataException("待同步操作记录超出限制，请保留数据并检查。");
    }
    public IReadOnlyList<PendingOperation> Pending=>pending.Values.ToArray();
    public PendingOperation Ensure(string kind,string endpoint,object payload)
    {
        var json=JsonSerializer.SerializeToElement(payload);
        var identity=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(kind+"\n"+endpoint+"\n"+json.GetRawText())));
        if(pending.TryGetValue(identity,out var existing))return existing;
        if(pending.Count>=128)throw new InvalidOperationException("待同步操作过多，请先重试同步已有操作。");
        var operation=new PendingOperation(identity,Guid.NewGuid().ToString(),kind,endpoint,json);
        pending.Add(identity,operation);
        try{Save();}catch{pending.Remove(identity);throw;}
        return operation;
    }
    public void Complete(PendingOperation operation)
    {
        if(!pending.TryGetValue(operation.Identity,out var current)||current.Key!=operation.Key)return;
        pending.Remove(operation.Identity);
        try{Save();}catch{pending[operation.Identity]=operation;throw;}
    }
    public void DismissAll()
    {
        var previous=pending.ToArray();pending.Clear();
        try{Save();}catch{foreach(var row in previous)pending.Add(row.Key,row.Value);throw;}
    }
    private void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var partial=path+"."+Guid.NewGuid().ToString("N")+".partial";
        try
        {
            using(var file=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {JsonSerializer.Serialize(file,pending);file.Flush(true);}
            File.Move(partial,path,true);
        }
        finally{if(File.Exists(partial))File.Delete(partial);}
    }
}
