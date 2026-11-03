#if DEBUG
using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace PDFMathTranslate.Desktop;

// In-process tests of this application's real views and production ViewModel.
// No input injection, screen scraping, or automation of other Windows apps.
internal static class NativeUiVerification
{
    internal static async Task RunAsync(MainWindow window,WorkbenchViewModel vm,string scenarioPath)
    {
        using var doc=JsonDocument.Parse(File.ReadAllText(scenarioPath));
        var scenario=doc.RootElement;
        var root=Path.GetFullPath(scenario.GetProperty("output_root").GetString()!);
        var allowed=Path.GetFullPath(Path.Combine(Environment.GetEnvironmentVariable("PDF2ZH_APP_ROOT")!,"docs","verification","native-desktop"))+Path.DirectorySeparatorChar;
        if(!root.StartsWith(allowed,StringComparison.OrdinalIgnoreCase)||Directory.Exists(root)) throw new InvalidOperationException("测试输出必须是本项目的新证据目录。");
        Directory.CreateDirectory(root);
        var checks=new Dictionary<string,object>();
        var success=false;
        try
        {
            checks["api_ready"]=vm.Ready;
            checks["real_window_visible"]=window.IsVisible;
            checks["window_handle"]=new System.Windows.Interop.WindowInteropHelper(window).Handle.ToInt64();
            checks["window_ready_ms"]=window.WindowReadyMs;
            checks["api_ready_ms"]=(DateTime.UtcNow-Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds;
            checks["render_kind"]="actual running WPF visual tree, RenderTargetBitmap; not OS input automation";
            await Capture(window,root,"01-workbench.png");
            window.ShowPage(typeof(SettingsPage)); await Capture(window,root,"02-settings.png");
            window.ShowSettingsStorage(true);await Capture(window,root,"02b-save-directory.png");window.ShowSettingsStorage(false);
            window.ShowPage(typeof(TasksPage)); await Capture(window,root,"03-queue.png");
            if(!vm.Ready) throw new InvalidOperationException("后台尚未就绪："+vm.Notice);
            if(scenario.TryGetProperty("idle_seconds",out var idle))
            {
                await Wait(()=>vm.AssetsReady,TimeSpan.FromSeconds(45));
                File.WriteAllText(Path.Combine(root,"performance-ready.json"),JsonSerializer.Serialize(new{ui_pid=Environment.ProcessId,control_pid=vm.BackendProcessId,window_ready_ms=window.WindowReadyMs,api_ready_ms=checks["api_ready_ms"],resources_ready_ms=(DateTime.UtcNow-Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds,idle_started_utc=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0}));
                await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(idle.GetInt32(),1,360)));
                File.WriteAllText(Path.Combine(root,"performance-idle-finished.json"),JsonSerializer.Serialize(new{idle_finished_utc=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0}));
            }
            if(scenario.TryGetProperty("sample",out var sample))
            {
                var endpoint=new Uri(scenario.GetProperty("mock_base_url").GetString()!);
                if(!endpoint.IsLoopback||endpoint.Scheme!="http")throw new InvalidOperationException("自动验收只允许本地测试提供方。");
                vm.Service="OpenAI";vm.Model="local-test-model";vm.BaseUrl=endpoint.ToString();vm.NewApiKey="local-fixture-only";
                vm.SaveDirectory=Path.Combine(root,"exports");
                await vm.SaveSettingsCommand.ExecuteAsync(null);
                vm.TargetLanguage=LanguageChoices.Resolve(vm.Languages,"fa");vm.AutoCheckUpdates=false;
                await vm.SaveSettingsCommand.ExecuteAsync(null);
                checks["uncommon_language_readback"]=vm.TargetLanguage?.Code=="fa";
                checks["auto_update_opt_out_readback"]=!vm.AutoCheckUpdates;
                if(vm.TargetLanguage?.Code!="fa"||vm.AutoCheckUpdates)throw new InvalidOperationException("语言或自动更新偏好未能正确读回");
                vm.SourceLanguage=vm.Languages.First(x=>x.Code=="en");vm.TargetLanguage=vm.Languages.First(x=>x.Code=="zh-CN");
                vm.AutoCheckUpdates=true;await vm.SaveSettingsCommand.ExecuteAsync(null);
                window.ShowPage(typeof(WorkbenchPage));await vm.ImportAsync([sample.GetString()!]);
                await Task.Delay(1000);
                await Capture(window,root,"04-imported-source.png");
                if(vm.Files.Count!=1)throw new InvalidOperationException("原生导入流程未完成："+vm.Notice);
                await Wait(()=>vm.AssetsState.Contains("可以开始翻译"),TimeSpan.FromSeconds(30));
                await vm.SubmitCommand.ExecuteAsync(null);
                var task=vm.SelectedTask??throw new InvalidOperationException("原生提交未产生任务："+vm.Notice);
                window.ShowPage(typeof(TasksPage));await Capture(window,root,"05-task-running.png");
                await Wait(()=>task.Terminal,TimeSpan.FromMinutes(3));
                checks["task_status"]=task.Status;checks["shared_task_reference"]=ReferenceEquals(task,vm.Store.Tasks.First(x=>x.Id==task.Id));
                if(task.Status!="done")throw new InvalidOperationException(task.Error);
                var translated=await vm.PreviewAsync(2,true,CancellationToken.None);
                checks["translated_preview_page_count"]=translated?.Pages;
                if(translated is null||translated.Pages<2||translated.Page!=2)throw new InvalidOperationException("译文预览页数或翻页读取错误");
                vm.LoseNextExportResponse();await vm.ExportCommand.ExecuteAsync(null);
                checks["lost_export_response_pending"]=vm.PendingOperations==1;
                if(vm.PendingOperations!=1)throw new InvalidOperationException("丢失响应后未保留原保存标识");
                await vm.ResumePendingCommand.ExecuteAsync(null);
                if(task.SavedPaths.Split(Environment.NewLine,StringSplitOptions.RemoveEmptyEntries).Length!=2)throw new InvalidOperationException("保存响应恢复产生重复版本");
                checks["lost_export_response_no_duplicate"]=true;
                await vm.ExportCommand.ExecuteAsync(null);
                checks["saved_versions"]=task.SavedPaths.Split(Environment.NewLine,StringSplitOptions.RemoveEmptyEntries).Length;
                if((int)checks["saved_versions"]!=4)throw new InvalidOperationException("显式第二次保存未生成预期版本");
                window.ShowPage(typeof(ResultsPage));await Capture(window,root,"06-results-versions.png");
                window.ShowPage(typeof(SettingsPage));await Capture(window,root,"07-effective-settings.png");
                window.ShowSettingsStorage(true);await Capture(window,root,"07b-save-directory.png");window.ShowSettingsStorage(false);
            }
            window.Width=980;window.Height=680;window.ShowPage(typeof(WorkbenchPage));await Capture(window,root,"08-compact-980.png");
            await Capture(window,root,"09-render-150-percent.png",1.5);
            await Capture(window,root,"10-render-200-percent.png",2);
            checks["dpi_scope"]="100/150/200 percent raster rendering of the same real WPF layout; system DPI and dialogs require manual verification";
            checks["manual_pending"]=new[]{"native file/folder picker keyboard and mouse input","OS drag/drop","cross-monitor DPI"};
            success=true;
        }
        catch(Exception ex){checks["error"]=ex.Message;await Capture(window,root,"failed-state.png");}
        finally
        {
            checks["passed"]=success;checks["completed_at"]=DateTimeOffset.Now;checks["process_id"]=Environment.ProcessId;
            File.WriteAllText(Path.Combine(root,"ui-result.json"),JsonSerializer.Serialize(checks,new JsonSerializerOptions{WriteIndented=true}));
            window.AutomatedClose=true;vm.Dispose();Application.Current.Shutdown(success?0:1);
        }
    }
    private static async Task Wait(Func<bool> condition,TimeSpan timeout)
    {
        var clock=Stopwatch.StartNew();while(!condition()){if(clock.Elapsed>timeout)throw new TimeoutException("原生流程等待超时");await Task.Delay(100);}
    }
    private static async Task Capture(MainWindow window,string root,string name,double scale=1)
    {
        window.UpdateLayout();await window.Dispatcher.InvokeAsync(()=>{},DispatcherPriority.Render);await Task.Delay(180);
        var bitmap=new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth*scale),(int)Math.Ceiling(window.ActualHeight*scale),96*scale,96*scale,PixelFormats.Pbgra32);
        bitmap.Render(window);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output=File.Create(Path.Combine(root,name));encoder.Save(output);
    }
}
#endif
