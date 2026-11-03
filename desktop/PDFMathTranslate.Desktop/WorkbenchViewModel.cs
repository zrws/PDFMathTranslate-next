using System.Collections.ObjectModel;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace PDFMathTranslate.Desktop;

public partial class WorkbenchViewModel : ObservableObject, IDisposable
{
    public TaskStore Store { get; } = new();
    public ObservableCollection<ImportedFile> Files { get; } = [];
    public ObservableCollection<string> Services { get; } = [];
    public ObservableCollection<GlossaryRow> GlossaryRows {get;}=[];
    public ObservableCollection<Choice> Languages { get; } = [new("auto","自动检测"), new("en","英语"),new("zh-CN","简体中文"),new("zh-TW","繁体中文"),new("ja","日语"),new("ko","韩语"),new("de","德语"),new("fr","法语"),new("es","西班牙语"),new("ru","俄语"),new("pt","葡萄牙语"),new("it","意大利语"),new("ar","阿拉伯语"),new("vi","越南语"),new("id","印度尼西亚语")];
    public IEnumerable<Choice> TargetLanguages => Languages.Where(x=>x.Code!="auto");
    public Choice[] Tiers { get; } = [new("eco","节能"),new("balanced","均衡（默认）"),new("performance","性能")];
    private readonly BackendSupervisor supervisor = new();
    private CancellationTokenSource life = new();
    private BackendClient? client;
    private OperationOutbox? outbox;
    private bool disposed;
    [ObservableProperty] private string serviceState = "窗口已就绪 · 正在启动翻译服务…";
    [ObservableProperty] private string syncState = "等待服务";
    [ObservableProperty] private string notice = "导入 PDF，确认语言和保存目录后开始翻译。";
    [ObservableProperty] private string assetsState = "资源尚未检查";
    [ObservableProperty] private double assetsProgress;
    [ObservableProperty] private string effectivePolicy = "生效值将在服务就绪后显示";
    [ObservableProperty] private string saveDirectory = "";
    [ObservableProperty] private string taskDirectory = "";
    [ObservableProperty] private string service = "";
    [ObservableProperty] private string model = "";
    [ObservableProperty] private string baseUrl = "";
    [ObservableProperty] private string apiKeyState = "未设置";
    [ObservableProperty] private string qps = "4";
    [ObservableProperty] private string pages = "";
    [ObservableProperty] private string glossary = "";
    [ObservableProperty] private string dataDirectory = "";
    [ObservableProperty] private bool dual = true;
    [ObservableProperty] private bool mono = true;
    [ObservableProperty] private bool autoTerms;
    [ObservableProperty] private bool ready;
    [ObservableProperty] private bool assetsReady;
    [ObservableProperty] private bool autoCheckUpdates=true;
    public string VersionDescription {get{var version=UpdateService.ReadVersion(RuntimePaths.OptionalEnvironment("PDF2ZH_APP_ROOT")??AppContext.BaseDirectory);return version.Preview?"开发预览 · 正式更新源已停用":$"版本 {version.Version}";}}
    public bool CanSubmit=>Ready&&AssetsReady&&Files.Count>0&&SourceLanguage!=null&&TargetLanguage!=null;
    [ObservableProperty] private string updateState="尚未检查更新";
    [ObservableProperty] private bool canDownloadUpdate;
    [ObservableProperty] private bool canInstallUpdate;
    private UpdatePackage? availableUpdate;
    private string? updateFile;
    [ObservableProperty] private ImportedFile? selectedFile;
    [ObservableProperty] private TaskRow? selectedTask;
    [ObservableProperty] private Choice? sourceLanguage;
    [ObservableProperty] private Choice? targetLanguage;
    [ObservableProperty] private Choice? tier;
    public string NewApiKey { private get; set; } = "";
    public string LanguageSummary => $"{SourceLanguage?.Label ?? "请选择源语言"} → {TargetLanguage?.Label ?? "请选择目标语言"}";
    public event Action? SelectionChanged;
    public WorkbenchViewModel() { SourceLanguage=Languages[1]; TargetLanguage=Languages[2]; Tier=Tiers[1];Files.CollectionChanged+=(_,_)=>CommandsChanged();Store.PropertyChanged+=(_,_)=>CommandsChanged(); }
    private void CommandsChanged(){OnPropertyChanged(nameof(CanSubmit));SubmitCommand.NotifyCanExecuteChanged();CancelCommand.NotifyCanExecuteChanged();RetryCommand.NotifyCanExecuteChanged();ExportCommand.NotifyCanExecuteChanged();}
    partial void OnReadyChanged(bool value)=>CommandsChanged();
    partial void OnAssetsReadyChanged(bool value)=>CommandsChanged();
    partial void OnSourceLanguageChanged(Choice? value) {OnPropertyChanged(nameof(LanguageSummary));CommandsChanged();}
    partial void OnTargetLanguageChanged(Choice? value) {OnPropertyChanged(nameof(LanguageSummary));CommandsChanged();}
    partial void OnSelectedFileChanged(ImportedFile? value) => SelectionChanged?.Invoke();
    partial void OnSelectedTaskChanged(TaskRow? value) {OnPropertyChanged(nameof(SelectedTask));CommandsChanged();SelectionChanged?.Invoke();}
    private static Task OnUi(Action action) => Application.Current.Dispatcher.InvokeAsync(action).Task;
    public async Task InitializeAsync()
    {
        Ready=false;
        try
        {
            life.Cancel(); life.Dispose(); life=new CancellationTokenSource();
            client=await supervisor.StartAsync(life.Token);
            var health=await client.JsonAsync("api/health",ct:life.Token);
            DataDirectory=health.GetProperty("data_dirs").GetProperty("home").GetString()!;
            UpdateState=UpdateService.ReadVersion(RuntimePaths.OptionalEnvironment("PDF2ZH_APP_ROOT")??AppContext.BaseDirectory).Preview?"开发预览，正式更新源已停用":"尚未检查更新";
            outbox=new OperationOutbox(DataDirectory);
            ServiceState="窗口已就绪 · 翻译服务已就绪";
            await ReadSettingsAsync();
            var prefs=await client.JsonAsync("api/prefs"); SaveDirectory=prefs.GetProperty("download_dir").GetString() ?? "";
            ApplyAssets(await client.JsonAsync("api/assets/status"));
            Ready=true;
            _ = ListenAsync(life.Token);
            await ResumePendingAsync();
            _=AutomaticUpdateAsync(life.Token);
        }
        catch(Exception ex) { ServiceState="服务未就绪 · 可重试启动"; Notice="启动失败："+Friendly(ex); }
    }
    private async Task ListenAsync(CancellationToken ct)
    {
        try { await client!.EventsAsync(async (type,envelope)=>await OnUi(()=> { if(ct.IsCancellationRequested)return;var selectedId=SelectedTask?.Id;Store.Apply(type,envelope); if(type=="assets.updated") ApplyAssets(envelope.GetProperty("data"));if(type=="snapshot"){if(envelope.GetProperty("data").TryGetProperty("assets",out var a))ApplyAssets(a);SelectedTask=Store.Tasks.FirstOrDefault(x=>x.Id==selectedId);} if(SelectedTask!=null) OnPropertyChanged(nameof(SelectedTask)); }), text=>_ = OnUi(()=>{if(!ct.IsCancellationRequested)SyncState=text;}),ct); }
        catch(OperationCanceledException) { }
    }
    private void ApplyAssets(JsonElement data)
    {
        AssetsState=data.GetProperty("message").GetString() ?? "";
        AssetsReady=data.GetProperty("state").GetString()=="ready";
        var total=data.GetProperty("total_bytes").GetDouble(); var done=data.GetProperty("completed_bytes").GetDouble();
        AssetsProgress=total>0 ? Math.Clamp(done/total*100,0,100) : 0;
    }
    private async Task ReadSettingsAsync()
    {
        var settings=await client!.JsonAsync("api/settings");
        Services.Clear(); foreach(var s in settings.GetProperty("services").EnumerateArray()) Services.Add(s.GetString()!);
        Service=settings.GetProperty("service").GetString() ?? ""; Model=settings.GetProperty("model").GetString() ?? ""; BaseUrl=settings.GetProperty("base_url").GetString() ?? "";
        ApiKeyState=settings.GetProperty("api_key_set").GetBoolean() ? "已保存密钥（不回显）" : "尚未设置密钥";
        AutoCheckUpdates=!settings.TryGetProperty("auto_update",out var auto)||auto.GetBoolean();
        Qps=settings.GetProperty("requested_qps").GetInt32().ToString();
        Tier=Tiers.FirstOrDefault(x=>x.Code==settings.GetProperty("resource_tier").GetString()) ?? Tiers[1];
        var policy=settings.GetProperty("effective_policy");
        EffectivePolicy=$"生效：同时 1 份文档 · 本地 {policy.GetProperty("local_compute_threads").GetInt32()} 线程 · 远程 {policy.GetProperty("api_qps_cap").GetInt32()} QPS / {policy.GetProperty("api_inflight_limit").GetInt32()} 并发 · CPU 模式";
        SourceLanguage=LanguageChoices.Resolve(Languages,settings.GetProperty("lang_in").GetString());
        var target=LanguageChoices.Resolve(Languages,settings.GetProperty("lang_out").GetString());
        OnPropertyChanged(nameof(TargetLanguages));TargetLanguage=target?.Code=="auto"?null:target;
    }
    public async Task ImportAsync(IEnumerable<string> paths)
    {
        if(client==null || !Ready) { Notice="服务尚未就绪，请先重试启动。"; return; }
        foreach(var path in paths)
        {
            if(!path.EndsWith(".pdf",StringComparison.OrdinalIgnoreCase)) { Notice="仅支持 PDF 文件。"; continue; }
            try { Notice="正在上传并读取页数："+Path.GetFileName(path); var file=await client.UploadAsync(path,life.Token); Files.Add(file); SelectedFile=file; Notice=$"已导入 {file.Filename}，共 {file.Pages} 页。"; }
            catch(Exception ex) { Notice="导入失败："+Friendly(ex); }
        }
    }
    [RelayCommand(CanExecute=nameof(CanSubmit))] private async Task SubmitAsync()
    {
        if(client==null || !Ready || Files.Count==0) { Notice="请先导入 PDF，并等待服务就绪。"; return; }
        if(TargetLanguage==null || SourceLanguage==null || !Dual && !Mono) { Notice="请选择源语言、目标语言，并至少保留一种输出。"; return; }
        try
        {
            foreach(var file in Files.ToArray())
            {
                var payload=new { file_id=file.Id,lang_in=SourceLanguage.Code,lang_out=TargetLanguage.Code,pages=Pages,no_dual=!Dual,no_mono=!Mono,auto_term_extraction=AutoTerms,export_dir=string.IsNullOrWhiteSpace(TaskDirectory)?SaveDirectory:TaskDirectory };
                var operation=outbox!.Ensure("create","api/tasks",payload);
                var task=await SendPending(operation); Store.Merge(task); SelectedTask=Store.Tasks.First(x=>x.Id==task.GetProperty("id").GetString()); Files.Remove(file);
            }
            Notice="任务已加入队列 · "+LanguageSummary+"。完成后请点击「保存结果」。";
        }
        catch(Exception ex) { Notice="提交未完成："+Friendly(ex)+" 可直接重试，同一请求不会重复创建任务。"; }
    }
    private bool CanCancel()=>SelectedTask?.Status is "queued" or "running";
    private bool CanRetry()=>SelectedTask?.Status is "failed" or "cancelled";
    private bool CanExport()=>SelectedTask?.Status=="done";
    [RelayCommand(CanExecute=nameof(CanCancel))] private async Task CancelAsync() => await TaskAction("cancel");
    [RelayCommand(CanExecute=nameof(CanRetry))] private async Task RetryAsync() => await TaskAction("retry");
    private async Task TaskAction(string action)
    {
        if(client==null || SelectedTask==null) return;
        try { var endpoint=$"api/tasks/{SelectedTask.Id}/{action}";var task=action=="retry"?await SendPending(outbox!.Ensure("retry",endpoint,new{})):await client.JsonAsync(endpoint,HttpMethod.Post,new{}); Store.Merge(task);if(action=="retry")SelectedTask=Store.Tasks.First(x=>x.Id==task.GetProperty("id").GetString()); Notice=action=="cancel"?"已发送取消请求。":"已按原配置重试。"; }
        catch(Exception ex) { Notice=Friendly(ex); }
    }
    [RelayCommand(CanExecute=nameof(CanExport))] private async Task ExportAsync()
    {
        if(client==null || SelectedTask?.Status!="done") { Notice="请选择已完成的任务。"; return; }
        try { Notice="正在保存结果，请稍候…"; var operation=outbox!.Ensure("export",$"api/tasks/{SelectedTask.Id}/export",new { directory=SelectedTask.PlannedDirectory.Length>0?SelectedTask.PlannedDirectory:SaveDirectory });var result=await SendPending(operation); Store.Merge(result); Notice=$"结果已保存，所选任务共有 {result.GetProperty("saved_paths").GetArrayLength()} 个保存路径。可查看任务详情或打开结果目录。"; }
        catch(Exception ex) { Notice="保存状态待同步确认："+Friendly(ex)+" 请重试同步，已产生的文件会沿用原版本路径。"; }
    }
    [RelayCommand] private async Task MoreHistoryAsync()
    {
        if(client==null || Store.HistoryCursor==null) return;
        try { Store.AddHistory(await client.JsonAsync("api/history?limit=50&cursor="+Uri.EscapeDataString(Store.HistoryCursor))); } catch(Exception ex) { Notice=Friendly(ex); }
    }
    [RelayCommand] private async Task ClearHistoryAsync()
    { if(client==null) return; try { await client.JsonAsync("api/tasks",HttpMethod.Delete); Notice="已清除终态历史，进行中的任务继续保留。"; } catch(Exception ex) { Notice=Friendly(ex); } }
    [RelayCommand] private async Task SaveSettingsAsync()
    {
        if(client==null) return;
        try
        {
            if(!int.TryParse(Qps,out var qps) || qps<1 || qps>1000) throw new InvalidOperationException("QPS 需为 1–1000 的整数。");
            var fields=new Dictionary<string,object?> { ["service"]=Service,["model"]=Model,["base_url"]=BaseUrl,["qps"]=qps,["resource_tier"]=Tier?.Code??"balanced",["lang_in"]=SourceLanguage?.Code,["lang_out"]=TargetLanguage?.Code,["download_dir"]=SaveDirectory };
            if(NewApiKey.Length>0) fields["api_key"]=NewApiKey;
            fields["auto_update"]=AutoCheckUpdates;
            await client.JsonAsync("api/settings",HttpMethod.Put,fields); NewApiKey="";
            await ReadSettingsAsync(); Notice="设置已保存，并已读回后端实际生效值。";
        }
        catch(Exception ex) { Notice="设置未保存："+Friendly(ex); }
    }
    [RelayCommand] private async Task PrepareAssetsAsync()
    { if(client==null) return; try { ApplyAssets(await client.JsonAsync("api/assets/prepare",HttpMethod.Post,new { })); } catch(Exception ex) { Notice=Friendly(ex); } }
    [RelayCommand] private async Task CancelAssetsAsync()
    {if(client==null)return;try{ApplyAssets(await client.JsonAsync("api/assets/cancel",HttpMethod.Post,new{}));}catch(Exception ex){Notice=Friendly(ex);}}
    [RelayCommand] private async Task RestartServiceAsync() => await InitializeAsync();
    private async Task<JsonElement> SendPending(PendingOperation operation)
    {
        object body=operation.Payload;
        if(operation.Kind=="export")body=new{directory=operation.Payload.GetProperty("directory").GetString(),export_id=operation.Key};
        var result=await client!.JsonAsync(operation.Endpoint,HttpMethod.Post,body,operation.Key,life.Token);
        outbox!.Complete(operation);return result;
    }
    [RelayCommand] private async Task ResumePendingAsync()
    {
        if(client==null||outbox==null)return;
        foreach(var operation in outbox.Pending)
        {
            try{Store.Merge(await SendPending(operation));Notice="待同步操作已恢复，沿用原请求标识。";}
            catch(Exception){Notice="有操作待同步，请检查服务后点击「重试待同步操作」。已保存的文件会沿用原版本路径。";}
        }
    }
    [RelayCommand] private void DismissPending()
    {
        if(outbox==null||outbox.Pending.Count==0){Notice="没有待同步操作。";return;}
        var details=string.Join(Environment.NewLine,outbox.Pending.Select(x=>(x.Kind switch{"export"=>"保存结果","retry"=>"重试任务",_=>"提交任务"})+" · "+x.Key));
        if(MessageBox.Show($"以下 {outbox.Pending.Count} 项操作的结果尚未确认：\n{details}\n\n清除记录不会撤销已接收的任务或文件。请先核对队列和保存目录；清除后再次操作会使用新标识。确定清除？","清除待同步记录",MessageBoxButton.YesNo,MessageBoxImage.Warning)!=MessageBoxResult.Yes)return;
        try{outbox.DismissAll();Notice="已清除待同步记录，任务与文件保留。";}catch(Exception){Notice="记录未能清除，请检查数据目录空间后重试。";}
    }
    [RelayCommand] private async Task CheckUpdateAsync()
    {
        var root=RuntimePaths.OptionalEnvironment("PDF2ZH_APP_ROOT")??AppContext.BaseDirectory;
        var current=UpdateService.ReadVersion(root);
        if(current.Preview){UpdateState=Notice="当前为开发预览，正式更新检查已停用。";return;}
        try
        {
            using var http=UpdateService.CreateClient();var updates=new UpdateService(http,false);
            using var deadline=CancellationTokenSource.CreateLinkedTokenSource(life.Token);deadline.CancelAfter(TimeSpan.FromSeconds(15));
            availableUpdate=await updates.CheckAsync(current.Version,deadline.Token);CanDownloadUpdate=availableUpdate!=null;
            UpdateState=availableUpdate==null?"当前已是最新版本。":$"发现 {availableUpdate.Version}，可下载更新。";
        }
        catch(Exception){UpdateState="更新检查失败，请检查网络后重试，当前版本可继续使用。";}
    }
    private async Task AutomaticUpdateAsync(CancellationToken ct)
    {
        var root=RuntimePaths.OptionalEnvironment("PDF2ZH_APP_ROOT")??AppContext.BaseDirectory;
        if(!AutoCheckUpdates||UpdateService.ReadVersion(root).Preview)return;
        try{await Task.Delay(8000,ct);if(ct.IsCancellationRequested||!AutoCheckUpdates)return;await CheckUpdateAsync();if(availableUpdate!=null)Notice="发现新版本，可在「资源与设置」中下载更新。";}
        catch(OperationCanceledException){}
    }
    [RelayCommand] private async Task DownloadUpdateAsync()
    {
        if(availableUpdate==null)return;
        try{using var http=UpdateService.CreateClient();var updates=new UpdateService(http,false);updateFile=await updates.DownloadAsync(availableUpdate,Path.Combine(DataDirectory,"updates"),(done,total)=>_ = OnUi(()=>UpdateState=total>0?$"正在下载更新 {done*100/total}%":"正在下载更新…"),life.Token);CanInstallUpdate=true;UpdateState="更新已下载并通过校验，可安装。";}
        catch(Exception){UpdateState="更新下载或校验失败，当前版本未改变，请重试。";}
    }
    [RelayCommand] private void InstallUpdate()
    {
        if(updateFile==null||availableUpdate==null||!CanInstallUpdate)return;
        if(Store.Tasks.Any(x=>!x.Terminal)){Notice="请先完成或取消当前任务，再安装更新。";return;}
        try{UpdateService.LaunchInstaller(updateFile,availableUpdate.Sha256);}
        catch(Exception){CanInstallUpdate=false;UpdateState="更新安装未启动，请重新下载后重试。";Notice="更新未启动，当前翻译服务继续运行，可重新下载更新。";return;}
        Dispose();Application.Current.Shutdown();
    }
    public async Task<PreviewFrame?> PreviewAsync(int page, bool output, CancellationToken ct)
    {
        if(client==null) return null;
        if(output && SelectedTask?.Status=="done") return await client.PreviewAsync($"api/tasks/{SelectedTask.Id}/preview?kind={(SelectedTask.Kinds.Contains("dual")?"dual":"mono")}&page={page}&width=1200",ct);
        if(SelectedFile==null) return SelectedTask==null?null:await client.PreviewAsync($"api/tasks/{SelectedTask.Id}/source-preview?page={page}&width=1200",ct);
        return await client.PreviewAsync($"api/files/{Uri.EscapeDataString(SelectedFile.Id)}/preview?page={page}&width=1200",ct);
    }
    private void ReadGlossary(JsonElement rows){GlossaryRows.Clear();foreach(var row in rows.EnumerateArray())GlossaryRows.Add(new(row.GetProperty("source").GetString()??"",row.GetProperty("target").GetString()??"",row.TryGetProperty("file",out var f)?Path.GetFileName(f.GetString()??""):""));}
    public async Task LoadGlossaryAsync() { if(client!=null) ReadGlossary(await client.JsonAsync("api/glossary")); }
    public async Task ImportGlossaryAsync(string path){if(client==null)return;try{ReadGlossary(await client.UploadGlossaryAsync(path));Notice="术语表已导入，后续任务生效。";}catch(Exception ex){Notice="术语表导入失败："+Friendly(ex);}}
#if DEBUG
    internal async Task<bool> VerifyMissingInstallerKeepsService()
    {
        var previous=availableUpdate;var oldFile=updateFile;var oldInstall=CanInstallUpdate;
        availableUpdate=new UpdatePackage(new Version(99,0),new Uri("http://127.0.0.1:9/never-requested"),new string('0',64),1,"");
        updateFile=Path.Combine(DataDirectory,"updates","missing-"+Guid.NewGuid().ToString("N")+".exe");CanInstallUpdate=true;
        try{InstallUpdate();return (await client!.JsonAsync("api/health",ct:life.Token)).GetProperty("control_ready").GetBoolean();}
        finally{availableUpdate=previous;updateFile=oldFile;CanInstallUpdate=oldInstall;}
    }
    internal int BackendProcessId=>supervisor.ProcessId;
    internal void LoseNextExportResponse(){var fired=false;client!.SimulateLostResponse=path=>{if(!fired&&path.EndsWith("/export")){fired=true;return true;}return false;};}
    internal int PendingOperations=>outbox?.Pending.Count??0;
#endif
    private static string Friendly(Exception ex) => ex is OperationCanceledException ? "操作已取消或服务超时，请重试。" : ex.Message;
    public void Dispose() { if(disposed)return;disposed=true;life.Cancel();life.Dispose();supervisor.Dispose(); }
}
