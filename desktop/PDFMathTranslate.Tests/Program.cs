using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using PDFMathTranslate.Desktop;

var checks=new List<string>();
void Check(string name,bool condition){if(!condition)throw new Exception(name);checks.Add(name);}
JsonElement Json(object obj)=>JsonSerializer.SerializeToElement(obj);
object TaskData(int revision,string status,double progress=0)=>new{id="task",filename="科学论文.pdf",status,progress,revision,stage="测试阶段",lang_in="en",lang_out="zh-CN",outputs=new{},saved_paths=Array.Empty<string>()};
JsonElement Envelope(string instance,int seq,object data)=>Json(new{instance_id=instance,event_id=seq,data});
var store=new TaskStore();
store.Apply("snapshot",Envelope("one",1,new{tasks=new[]{TaskData(5,"running",40)}}));
var reference=store.Tasks.Single();
store.Apply("task.updated",Envelope("one",2,TaskData(4,"running",20)));
Check("old revision cannot regress progress",reference.Progress==40&&reference.Revision==5);
store.Apply("task.final",Envelope("one",3,TaskData(6,"done",100)));
store.Apply("task.updated",Envelope("one",4,TaskData(7,"running",60)));
Check("late progress cannot reopen terminal",reference.Status=="done"&&reference.Progress==100);
Check("one shared row survives updates",ReferenceEquals(reference,store.Tasks.Single()));
store.Apply("snapshot",Envelope("one",4,new{tasks=new[]{TaskData(8,"done",100)}}));
Check("reconnect snapshot preserves selected row reference",ReferenceEquals(reference,store.Tasks.Single())&&reference.Revision==8);
store.Apply("task.updated",Envelope("other",999,TaskData(9,"running",10)));
Check("foreign instance incremental ignored",store.InstanceId=="one"&&store.Watermark==4);
store.Apply("snapshot",Envelope("two",0,new{tasks=new[]{TaskData(8,"failed")}}));
Check("restart snapshot replaces old instance",store.InstanceId=="two"&&store.Tasks.Single().Status=="failed");
store.Apply("task.updated",Envelope("two",0,TaskData(9,"running")));
Check("duplicate sequence ignored",store.Tasks.Single().Status=="failed");
var installer=Encoding.UTF8.GetBytes("local fake installer: never executed");
var languages=new List<Choice>{new("en","英语"),new("zh-CN","简体中文")};
var custom=LanguageChoices.Resolve(languages,"fa");
Check("persisted uncommon language is preserved without replacing it with Chinese",custom?.Code=="fa"&&languages.Contains(custom));
Check("language readback reuses the same choice",ReferenceEquals(custom,LanguageChoices.Resolve(languages,"FA"))&&languages.Count==3);
Check("missing language remains visibly unselected",LanguageChoices.Resolve(languages,"")==null);
var sha=Convert.ToHexString(SHA256.HashData(installer));
var handler=new FixtureHandler(installer,sha);using var http=new HttpClient(handler);
var disabled=new UpdateService(http,true);
Check("development preview never calls formal feed",await disabled.CheckAsync(new Version(2,9,0))==null&&handler.Calls==0);
var updates=new UpdateService(http,true,new Uri("http://127.0.0.1/release"));
var package=await updates.CheckAsync(new Version(2,9,0));
Check("legacy latest.json protocol compares version",package?.Version==new Version(3,0,0));
Check("older update ignored",await updates.CheckAsync(new Version(4,0,0))==null);
var root=Path.Combine(Path.GetTempPath(),"pdf2zh-update-test-"+Guid.NewGuid().ToString("N"));
var target=await updates.DownloadAsync(package!,root);
var outbox=new OperationOutbox(root);var operation=outbox.Ensure("export","api/tasks/task/export",new{directory=root});
var restoredOutbox=new OperationOutbox(root);var replay=restoredOutbox.Ensure("export","api/tasks/task/export",new{directory=root});
Check("client lost response preserves export key across restart",operation.Key==replay.Key);
restoredOutbox.Complete(replay);var next=restoredOutbox.Ensure("export","api/tasks/task/export",new{directory=root});
Check("explicit next export creates a new version operation",next.Key!=replay.Key);
restoredOutbox.Complete(replay);
Check("late old completion cannot erase newer operation",restoredOutbox.Pending.Single().Key==next.Key);
restoredOutbox.DismissAll();
Check("explicit dismiss persists",new OperationOutbox(root).Pending.Count==0);
Check("closed-file SHA256 verifies on Windows",File.ReadAllBytes(target).SequenceEqual(installer));
try{await updates.DownloadAsync(package! with{Sha256=new string('0',64)},root);throw new Exception("wrong hash accepted");}catch(InvalidDataException){checks.Add("wrong installer hash refused");}
Check("failed download leaves no partial",!Directory.GetFiles(root,"*.partial").Any());
handler.RedirectOutside=true;var beforeRedirect=handler.Calls;
try{await updates.CheckAsync(new Version(2,9,0));throw new Exception("external redirect accepted");}catch(InvalidDataException){checks.Add("external test-feed redirect refused before request");}
Check("redirect makes no outside request",handler.Calls==beforeRedirect+1);handler.RedirectOutside=false;
handler.MissingHash=true;
try{await updates.CheckAsync(new Version(2,9,0));throw new Exception("missing hash accepted");}catch(Exception e)when(e is KeyNotFoundException or InvalidDataException){checks.Add("missing hash fails closed");}
var report=new{passed=true,checks,temporary_root=root,note="local fake release handler only; installer never executed"};
Console.WriteLine(JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));

sealed class FixtureHandler(byte[] installer,string sha):HttpMessageHandler
{
    public int Calls;public bool MissingHash;public bool RedirectOutside;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct)
    {
        if(request.RequestUri?.Host!="127.0.0.1")throw new Exception("external request forbidden");Calls++;
        if(RedirectOutside){var redirect=new HttpResponseMessage(HttpStatusCode.Redirect);redirect.Headers.Location=new Uri("http://192.0.2.1/forbidden");return Task.FromResult(redirect);}
        object? body=request.RequestUri.AbsolutePath switch{"/release"=>new{assets=new[]{new{name="latest.json",browser_download_url="http://127.0.0.1/latest.json"}}},"/latest.json"=>MissingHash?new Dictionary<string,object>{{"version","3.0.0"},{"url","http://127.0.0.1/setup.exe"}}:new{version="3.0.0",url="http://127.0.0.1/setup.exe",sha256=sha,size=installer.Length,notes="测试更新"},_=>null};
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=body==null?new ByteArrayContent(installer):new StringContent(JsonSerializer.Serialize(body),Encoding.UTF8,"application/json")});
    }
}
