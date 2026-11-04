using System.Collections.ObjectModel;
using System.Net.Http;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace PDFMathTranslate.Desktop;

public partial class WorkbenchViewModel
{
    public ObservableCollection<ChannelProfile> Channels {get;}=[];
    public ObservableCollection<string> DetectedModels {get;}=[];
    [ObservableProperty] private ChannelProfile? selectedChannel;
    [ObservableProperty] private string channelName="新渠道";
    [ObservableProperty] private string activeChannelName="等待服务";
    [ObservableProperty] private string activeModel="";
    [ObservableProperty] private string activeService="";
    public string ActiveChannelId {get;private set;}="";
    public int ActiveChannelRevision {get;private set;}
    private long channelDraftGeneration;
    private CancellationTokenSource? channelProbe;
    private void AdvanceChannelDraft(){channelDraftGeneration++;if(channelProbe!=null){channelProbe.Cancel();ChannelState="配置已改变，已取消旧探测；可按当前配置重新测试。";}}
    partial void OnServiceChanged(string value)=>AdvanceChannelDraft();
    partial void OnBaseUrlChanged(string value)=>AdvanceChannelDraft();
    partial void OnModelChanged(string value)=>AdvanceChannelDraft();
    partial void OnChannelNameChanged(string value)=>AdvanceChannelDraft();
    partial void OnClearChannelKeyChanged(bool value)=>AdvanceChannelDraft();
    [ObservableProperty] private string channelState="保存多个渠道，随时切换；密钥不会回显。";
    [ObservableProperty] private bool clearChannelKey;
    [ObservableProperty] private bool allPages=true;
    [ObservableProperty] private bool useSourceDirectory;
    [ObservableProperty] private bool importBusy;
    [ObservableProperty] private string batchState="支持一次选择多份 PDF，文档按队列逐份处理。";
    [ObservableProperty] private string exportDirectory="";
    [ObservableProperty] private bool exportToSource;
    [ObservableProperty] private bool exportDual=true;
    [ObservableProperty] private bool exportMono=true;
    [ObservableProperty] private bool exportGlossary;
    public event Action? ChannelDraftReset;
    public string SubmitLabel=>Files.Count>1?$"翻译全部 {Files.Count} 份":"开始翻译";
    public string WorkSaveDestination=>UseSourceDirectory?"每份源 PDF 旁边":string.IsNullOrWhiteSpace(TaskDirectory)?SaveDirectory:TaskDirectory;
    public string SubmissionSummary=>(AllPages?"全部页面":"指定页码")+" · "+(Dual&&Mono?"双语对照和仅译文":Dual?"双语对照":Mono?"仅译文":"请选择输出");
    partial void OnSaveDirectoryChanged(string value)=>OnPropertyChanged(nameof(WorkSaveDestination));
    partial void OnTaskDirectoryChanged(string value)=>OnPropertyChanged(nameof(WorkSaveDestination));
    partial void OnUseSourceDirectoryChanged(bool value)=>OnPropertyChanged(nameof(WorkSaveDestination));
    private readonly HashSet<string> batchTasks=[];
    public string BatchSummary {get{var tasks=Store.Tasks.Where(t=>batchTasks.Contains(t.Id)).ToArray();return tasks.Length==0?BatchState:$"本批 {tasks.Length} 份：完成 {tasks.Count(t=>t.Status=="done")}，进行中 {tasks.Count(t=>t.Status=="running")}，等待 {tasks.Count(t=>t.Status=="queued")}，失败或取消 {tasks.Count(t=>t.Status is "failed" or "cancelled")}";}}
    public string[] SelectedExportKinds=>new[]{ExportDual&&SelectedTask?.Kinds.Contains("dual")==true?"dual":null,ExportMono&&SelectedTask?.Kinds.Contains("mono")==true?"mono":null,ExportGlossary&&SelectedTask?.Kinds.Contains("glossary")==true?"glossary":null}.OfType<string>().ToArray();
    public string ExportDestination=>ExportToSource?SelectedTask?.SourceDirectory??"":ExportDirectory;
    public bool HasSourceDirectory=>!string.IsNullOrWhiteSpace(SelectedTask?.SourceDirectory);
    public bool HasSelectedTask=>SelectedTask!=null;
    public bool HasDualOutput=>SelectedTask?.Kinds.Contains("dual")==true;
    public bool HasMonoOutput=>SelectedTask?.Kinds.Contains("mono")==true;
    public bool HasGlossaryOutput=>SelectedTask?.Kinds.Contains("glossary")==true;
    partial void OnAllPagesChanged(bool value){if(value)Pages="";OnPropertyChanged(nameof(SubmissionSummary));}
    partial void OnImportBusyChanged(bool value)=>CommandsChanged();
    partial void OnExportDualChanged(bool value)=>CommandsChanged();
    partial void OnExportMonoChanged(bool value)=>CommandsChanged();
    partial void OnExportGlossaryChanged(bool value)=>CommandsChanged();
    partial void OnExportToSourceChanged(bool value)=>OnPropertyChanged(nameof(ExportDestination));
    partial void OnExportDirectoryChanged(string value)=>OnPropertyChanged(nameof(ExportDestination));
    partial void OnSelectedChannelChanged(ChannelProfile? value)
    {
        AdvanceChannelDraft();
        NewApiKey="";ClearChannelKey=false;ChannelDraftReset?.Invoke();DetectedModels.Clear();
        if(value==null)return;
        ChannelName=value.Name;Service=value.Service;BaseUrl=value.BaseUrl;Model=value.Model;
        ApiKeyState=value.ApiKeySet?"已保存此渠道密钥，留空保留":"此渠道尚未保存密钥";
        ChannelState=$"正在编辑「{value.Name}」，当前使用「{ActiveChannelName}」。";
    }
    private void ResetExportChoice(TaskRow? value)
    {
        exportTaskShape=OutputShape(value);
        ExportDirectory=value?.PlannedDirectory is {Length:>0} path?path:SaveDirectory;
        ExportToSource=value?.SaveMode=="source";ExportDual=HasDualOutput;ExportMono=HasMonoOutput;ExportGlossary=HasGlossaryOutput;
        foreach(var name in new[]{nameof(HasSourceDirectory),nameof(HasDualOutput),nameof(HasMonoOutput),nameof(HasGlossaryOutput),nameof(ExportDestination)})OnPropertyChanged(name);
    }
    private string exportTaskShape="";
    private static string OutputShape(TaskRow? value)=>value==null?"":value.Id+":"+string.Join(',',value.Kinds.Order());
    private void RefreshTaskOutputs(){if(exportTaskShape!=OutputShape(SelectedTask))ResetExportChoice(SelectedTask);OnPropertyChanged(nameof(BatchSummary));}
    private async Task ReadChannelsAsync(string? select=null)
    {
        if(client==null)return;
        var data=await client.JsonAsync("api/channels");var id=select??data.GetProperty("active_id").GetString();
        Channels.Clear();foreach(var p in data.GetProperty("profiles").EnumerateArray())Channels.Add(new(p.GetProperty("id").GetString()!,p.GetProperty("name").GetString()!,p.GetProperty("service").GetString()!,p.GetProperty("base_url").GetString()??"",p.GetProperty("model").GetString()??"",p.GetProperty("api_key_set").GetBoolean(),p.GetProperty("revision").GetInt32()));
        SelectedChannel=Channels.FirstOrDefault(p=>p.Id==id);
    }
    private Dictionary<string,object?> ChannelDraft(string? action=null)
    {
        var data=new Dictionary<string,object?> { ["id"]=SelectedChannel?.Id,["name"]=ChannelName,["service"]=Service,["base_url"]=BaseUrl,["model"]=Model };
        if(NewApiKey.Length>0||ClearChannelKey)data["api_key"]=ClearChannelKey?"":NewApiKey;
        if(action!=null)data["action"]=action;
        return data;
    }
    [RelayCommand] private void NewChannel()
    {SelectedChannel=null;ChannelName="新渠道";Service="OpenAICompatible";BaseUrl="";Model="";NewApiKey="";ClearChannelKey=false;ChannelDraftReset?.Invoke();ApiKeyState="填写新渠道密钥";ChannelState="新建渠道，保存后可在列表中恢复。";}
    [RelayCommand] private async Task SaveChannelAsync()
    {
        if(client==null)return;
        try{var data=await client.JsonAsync("api/channels",HttpMethod.Post,ChannelDraft());NewApiKey="";ClearChannelKey=false;SettingsSaved?.Invoke();await ReadSettingsAsync();await ReadChannelsAsync(data.GetProperty("active_id").GetString());ChannelState=Notice=$"已保存并使用「{ActiveChannelName}」。";}
        catch(Exception ex){ChannelState=Notice="渠道未保存："+Friendly(ex);}
    }
    [RelayCommand] private async Task ActivateChannelAsync()
    {
        if(client==null||SelectedChannel==null)return;
        try{await client.JsonAsync($"api/channels/{SelectedChannel.Id}/activate",HttpMethod.Post,new{});await ReadSettingsAsync();await ReadChannelsAsync();ChannelState=Notice=$"已切换到「{ActiveChannelName}」。";}
        catch(Exception ex){ChannelState=Notice=Friendly(ex);}
    }
    [RelayCommand] private async Task DeleteChannelAsync()
    {
        if(client==null||SelectedChannel==null)return;
        try{await client.JsonAsync($"api/channels/{SelectedChannel.Id}",HttpMethod.Delete);await ReadChannelsAsync();ChannelState=Notice="已删除渠道，其它渠道和任务保留。";}
        catch(Exception ex){ChannelState=Notice=Friendly(ex);}
    }
    [RelayCommand] private async Task TestChannelAsync()=>await ProbeChannelAsync(false);
    [RelayCommand] private async Task DiscoverModelsAsync()=>await ProbeChannelAsync(true);
    private async Task ProbeChannelAsync(bool models)
    {
        if(client==null)return;
        channelProbe?.Cancel();using var cancellation=CancellationTokenSource.CreateLinkedTokenSource(life.Token);channelProbe=cancellation;
        var generation=channelDraftGeneration;var request=ChannelDraft(models?"models":"test");
        try{ChannelState=models?"正在获取模型列表…":"正在发送简短渠道测试请求…";var data=await client.JsonAsync("api/channels/probe",HttpMethod.Post,request,ct:cancellation.Token);if(generation!=channelDraftGeneration||cancellation.IsCancellationRequested)return;if(models){DetectedModels.Clear();foreach(var m in data.GetProperty("models").EnumerateArray())DetectedModels.Add(m.GetString()!);if(!DetectedModels.Contains(Model))Model=DetectedModels.FirstOrDefault()??Model;}ChannelState=data.GetProperty("message").GetString()+$" {data.GetProperty("latency_ms").GetInt32()} ms";}
        catch(OperationCanceledException){}
        catch(Exception ex){if(generation==channelDraftGeneration&&!cancellation.IsCancellationRequested)ChannelState=Notice=Friendly(ex);}
        finally{if(ReferenceEquals(channelProbe,cancellation))channelProbe=null;}
    }
    [RelayCommand] private async Task SaveDirectoryAsync()
    {
        if(client==null)return;
        try{var prefs=await client.JsonAsync("api/prefs",HttpMethod.Put,new{download_dir=SaveDirectory,save_mode=UseSourceDirectory?"source":"custom"});SaveDirectory=prefs.GetProperty("download_dir").GetString()!;Notice="保存方式与默认目录已保存并读回。";}
        catch(Exception ex){Notice="目录未保存："+Friendly(ex);}
    }
    [RelayCommand] private void UseDefaultExportDirectory(){ExportToSource=false;ExportDirectory=SaveDirectory;}
    [RelayCommand] private void RemoveFile(ImportedFile? file){if(file==null||ImportBusy)return;Files.Remove(file);if(ReferenceEquals(SelectedFile,file))SelectedFile=Files.FirstOrDefault();}
    [RelayCommand] private void ClearFiles(){if(ImportBusy)return;Files.Clear();SelectedFile=null;}
}
