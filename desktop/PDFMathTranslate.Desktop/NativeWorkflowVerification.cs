#if DEBUG
using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;

namespace PDFMathTranslate.Desktop;

internal static class NativeWorkflowVerification
{
    private static void Check(Dictionary<string,object> checks,string name,bool passed)
    {checks[name]=passed;if(!passed)throw new InvalidOperationException("工作流验收失败："+name);}
    private static async Task Wait(Func<bool> condition,int seconds=30)
    {var watch=Stopwatch.StartNew();while(!condition()){if(watch.Elapsed.TotalSeconds>seconds)throw new TimeoutException("工作流等待超时");await Task.Delay(100);}}
    internal static async Task RunAsync(MainWindow window,WorkbenchViewModel vm,string root,JsonElement scenario,Dictionary<string,object> checks)
    {
        var endpoint=new Uri(scenario.GetProperty("mock_base_url").GetString()!);
        if(!endpoint.IsLoopback||endpoint.Scheme!="http")throw new InvalidOperationException("只允许回环夹具");
        using var fixture=new HttpClient(new SocketsHttpHandler{UseProxy=false,AllowAutoRedirect=false}){BaseAddress=endpoint,Timeout=TimeSpan.FromSeconds(5)};
        var samples=scenario.GetProperty("samples").EnumerateArray().Select(x=>Path.GetFullPath(x.GetString()!)).ToArray();
        var local=Path.GetFullPath(Path.Combine(Environment.GetEnvironmentVariable("PDF2ZH_APP_ROOT")!,".local"))+Path.DirectorySeparatorChar;
        if(samples.Length!=3||samples.Any(p=>!p.StartsWith(local,StringComparison.OrdinalIgnoreCase)))throw new InvalidOperationException("样本必须是本轮自有 .local 文件");
        var originals=samples.ToDictionary(p=>p,p=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))));
        window.ShowPage(typeof(SettingsPage));await Task.Delay(300);
        vm.NewChannelCommand.Execute(null);vm.ChannelName="论文主用渠道";vm.Service="OpenAI";vm.BaseUrl=new Uri(endpoint,"a/v1").ToString();vm.Model="owned-model-a";vm.NewApiKey="owned-ui-channel-secret-A";
        await vm.SaveChannelCommand.ExecuteAsync(null);
        Check(checks,"named_channel_A_saved",vm.ActiveChannelName=="论文主用渠道");var channelA=vm.Channels.Single(c=>c.Name=="论文主用渠道");
        vm.NewChannelCommand.Execute(null);vm.ChannelName="备用模型渠道";vm.Service="OpenAI";vm.BaseUrl=new Uri(endpoint,"b/v1").ToString();vm.Model="owned-model-b";vm.NewApiKey="owned-ui-channel-secret-B";
        await vm.SaveChannelCommand.ExecuteAsync(null);
        Check(checks,"named_channel_B_saved",vm.ActiveChannelName=="备用模型渠道");var channelB=vm.Channels.Single(c=>c.Name=="备用模型渠道");
        vm.SelectedChannel=vm.Channels.Single(c=>c.Id==channelA.Id);vm.BaseUrl=new Uri(endpoint,"slow/v1").ToString();
        var late=vm.DiscoverModelsCommand.ExecuteAsync(null);
        var seen=false;await Wait(()=>seen=fixture.GetStringAsync("probe-state").GetAwaiter().GetResult()=="started");
        vm.SelectedChannel=vm.Channels.Single(c=>c.Id==channelB.Id);var expected=vm.Model;
        await fixture.GetStringAsync("release-probe");await late;
        Check(checks,"late_model_probe_does_not_modify_other_channel",vm.Model==expected&&vm.DetectedModels.Count==0&&vm.SelectedChannel?.Id==channelB.Id);
        await vm.DiscoverModelsCommand.ExecuteAsync(null);
        Check(checks,"model_discovery_is_real",vm.DetectedModels.SequenceEqual(new[]{"owned-model-b"}));
        await vm.TestChannelCommand.ExecuteAsync(null);Check(checks,"channel_test_is_real",vm.ChannelState.Contains("成功"));
        await NativeUiVerification.Capture(window,root,"02-channel-management.png");
        vm.SaveDirectory=Path.Combine(root,"原默认目录");vm.UseSourceDirectory=true;await vm.SaveDirectoryCommand.ExecuteAsync(null);
        await vm.RestartServiceCommand.ExecuteAsync(null);
        Check(checks,"channels_and_directory_survive_backend_restart",vm.Ready&&vm.ActiveChannelName=="备用模型渠道"&&vm.UseSourceDirectory&&vm.SaveDirectory.EndsWith("原默认目录")&&vm.Channels.Any(c=>c.Id==channelA.Id));
        await vm.TestChannelCommand.ExecuteAsync(null);Check(checks,"protected_key_restored_after_restart",vm.ChannelState.Contains("成功"));
        vm.SelectedChannel=vm.Channels.Single(c=>c.Id==channelA.Id);await vm.ActivateChannelCommand.ExecuteAsync(null);
        await Wait(()=>vm.AssetsReady,60);
        window.ShowPage(typeof(WorkbenchPage));await Task.Delay(300);
        var workbench=NativeUiVerification.Descendants(window).OfType<WorkbenchPage>().Single();
        ((Wpf.Ui.Controls.ToggleSwitch)workbench.FindName("DualOption")).SetCurrentValue(Wpf.Ui.Controls.ToggleSwitch.IsCheckedProperty,true);
        ((Wpf.Ui.Controls.ToggleSwitch)workbench.FindName("MonoOption")).SetCurrentValue(Wpf.Ui.Controls.ToggleSwitch.IsCheckedProperty,false);
        Check(checks,"actual_output_controls_update_viewmodel",vm.Dual&&!vm.Mono);
        Check(checks,"all_pages_is_default",vm.AllPages);
        vm.Pages="1-5"; // A stale legacy draft must not limit explicit all-pages mode.
        await vm.ImportAsync(samples);
        Check(checks,"three_real_files_imported",vm.Files.Count==3&&vm.Files[0].Pages==7&&vm.SubmitLabel.Contains("3"));
        vm.SelectedFile=vm.Files[0];await workbench.VerifyPreviewAsync(1,false);
        window.Width=980;window.Height=680;
        await NativeUiVerification.Capture(window,root,"03-three-files-980.png");
        checks["compact_batch_layout"]=NativeUiVerification.VerifyWorkbench(window,workbench);
        var pending=(DataGrid)workbench.FindName("PendingFiles");var gridTop=pending.TransformToAncestor(window).Transform(new Point()).Y;
        var rowsVisible=Enumerable.Range(0,3).All(i=>pending.ItemContainerGenerator.ContainerFromIndex(i) is DataGridRow row&&row.TransformToAncestor(window).Transform(new Point()).Y+row.ActualHeight<=gridTop+pending.ActualHeight+1);
        Check(checks,"three_pending_rows_not_clipped",rowsVisible);
        window.Width=1400;window.Height=900;await NativeUiVerification.Capture(window,root,"04-batch-ready.png");
        if(scenario.TryGetProperty("workflow_layout_only",out var layoutOnly)&&layoutOnly.GetBoolean())return;
        var before=vm.Store.Tasks.Select(t=>t.Id).ToHashSet();var switched=false;
        vm.TestApi.BeforeReturn=async path=>
        {
            if(path!="api/tasks"||switched)return;
            switched=true;vm.TestApi.BeforeReturn=null;
            vm.SelectedChannel=vm.Channels.Single(c=>c.Id==channelB.Id);await vm.ActivateChannelCommand.ExecuteAsync(null);
        };
        await vm.SubmitCommand.ExecuteAsync(null);vm.TestApi.BeforeReturn=null;
        var batch=vm.Store.Tasks.Where(t=>!before.Contains(t.Id)).ToArray();
        Check(checks,"batch_created_three_distinct_tasks",batch.Length==3&&vm.Files.Count==0&&switched);
        foreach(var task in batch)
        {
            var configuration=await vm.TestApi.JsonAsync($"api/tasks/{task.Id}/configuration");
            Check(checks,"batch_channel_"+task.Id,configuration.GetProperty("channel_id").GetString()==channelA.Id&&configuration.GetProperty("pages").GetString()==""&&configuration.GetProperty("no_mono").GetBoolean());
        }
        window.ShowPage(typeof(TasksPage));await NativeUiVerification.Capture(window,root,"05-real-batch-queue.png");
        await Wait(()=>batch.All(t=>t.Terminal),900);
        Check(checks,"all_three_documents_really_completed",batch.All(t=>t.Status=="done"));
        Check(checks,"dual_only_has_no_mono_output",batch.All(t=>t.Kinds.SequenceEqual(new[]{"dual"})));
        var seven=batch.Single(t=>t.Filename==Path.GetFileName(samples[0]));vm.SelectedTask=seven;
        var seventh=await vm.PreviewAsync(7,true,CancellationToken.None);
        Check(checks,"actual_translated_page_seven",seventh is {Pages:>=7,Page:7});
        window.ShowPage(typeof(WorkbenchPage));await workbench.VerifyPreviewAsync(7,true);await NativeUiVerification.Capture(window,root,"06-translated-page-seven.png");
        foreach(var task in batch)
        {
            vm.SelectedTask=task;await vm.ExportCommand.ExecuteAsync(null);
            Check(checks,"source_export_"+task.Id,task.SavedFiles.Count==1&&Path.GetDirectoryName(task.SavedFiles[0].FullPath)==task.SourceDirectory&&task.SavedFiles[0].Filename.EndsWith("_双语对照.pdf"));
        }
        window.ShowPage(typeof(WorkbenchPage));await Task.Delay(300);
        ((Wpf.Ui.Controls.ToggleSwitch)workbench.FindName("DualOption")).SetCurrentValue(Wpf.Ui.Controls.ToggleSwitch.IsCheckedProperty,false);
        ((Wpf.Ui.Controls.ToggleSwitch)workbench.FindName("MonoOption")).SetCurrentValue(Wpf.Ui.Controls.ToggleSwitch.IsCheckedProperty,true);
        Check(checks,"mono_only_controls_update_viewmodel",!vm.Dual&&vm.Mono);
        vm.UseSourceDirectory=false;vm.SaveDirectory=Path.Combine(root,"自定义文章目录");await vm.SaveDirectoryCommand.ExecuteAsync(null);
        await vm.ImportAsync([samples[0]]);var ids=vm.Store.Tasks.Select(t=>t.Id).ToHashSet();await vm.SubmitCommand.ExecuteAsync(null);
        var mono=vm.Store.Tasks.Single(t=>!ids.Contains(t.Id));await Wait(()=>mono.Terminal,600);
        Check(checks,"mono_only_real_output",mono.Status=="done"&&mono.Kinds.SequenceEqual(new[]{"mono"}));
        vm.SelectedTask=mono;vm.LoseNextExportResponse();await vm.ExportCommand.ExecuteAsync(null);
        Check(checks,"lost_export_response_is_pending",vm.PendingOperations==1);
        await vm.ResumePendingCommand.ExecuteAsync(null);
        Check(checks,"lost_export_replay_is_one_file",vm.PendingOperations==0&&mono.SavedFiles.Count==1);
        var changed=Path.Combine(root,"实际更改后的保存目录");vm.SaveDirectory=changed;await vm.SaveDirectoryCommand.ExecuteAsync(null);vm.UseDefaultExportDirectoryCommand.Execute(null);
        await vm.ExportCommand.ExecuteAsync(null);await vm.ExportCommand.ExecuteAsync(null);
        Check(checks,"changed_directory_is_used_and_names_are_chinese",mono.SavedFiles.Count==3&&mono.SavedFiles.Count(f=>Path.GetDirectoryName(f.FullPath)==Path.Combine(changed,mono.ArticleTitle))==2&&mono.SavedFiles.Any(f=>f.Filename.EndsWith("_译文_第2版.pdf")));
        Check(checks,"original_pdf_bytes_unchanged",originals.All(p=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p.Key)))==p.Value));
        window.ShowPage(typeof(ResultsPage));await Task.Delay(300);
        var results=NativeUiVerification.Descendants(window).OfType<ResultsPage>().Single();
        var list=(ListBox)results.FindName("CompletedTasks");var view=(ListCollectionView)list.ItemsSource;
        Check(checks,"history_is_grouped_by_three_articles",view.Groups?.Count==3);
        await NativeUiVerification.Capture(window,root,"07-article-history-and-save-directory.png");
        vm.Appearance.ThemeChoice=vm.Appearance.Themes[1];await NativeUiVerification.Capture(window,root,"08-results-dark.png");vm.Appearance.ThemeChoice=vm.Appearance.Themes[0];
        var final=await vm.TestApi.JsonAsync("api/tasks");File.WriteAllText(Path.Combine(root,"actual-tasks.json"),final.GetRawText());
        await vm.RestartServiceCommand.ExecuteAsync(null);
        var health=await vm.TestApi.JsonAsync("api/health");await Wait(()=>vm.Store.InstanceId==health.GetProperty("instance_id").GetString());
        Check(checks,"final_preferences_and_channels_persist",vm.Ready&&vm.SaveDirectory==changed&&!vm.UseSourceDirectory&&vm.ActiveChannelName=="备用模型渠道"&&vm.Store.Tasks.Count==4);
        foreach(var p in Directory.EnumerateFiles(vm.DataDirectory,"*",SearchOption.AllDirectories).Where(p=>new[]{".json",".jsonl",".toml",".txt"}.Contains(Path.GetExtension(p))&&new FileInfo(p).Length<20*1024*1024))
        {
            var text=File.ReadAllText(p);if(text.Contains("owned-ui-channel-secret-A")||text.Contains("owned-ui-channel-secret-B"))throw new InvalidOperationException("本轮明文密钥出现在自有数据目录");
        }
        checks["channel_keys_absent_from_owned_text_files"]=true;
        checks["manual_pending"]=new[]{"OS file/folder dialog input","OS drag/drop","cross-monitor DPI"};
    }
}
#endif
