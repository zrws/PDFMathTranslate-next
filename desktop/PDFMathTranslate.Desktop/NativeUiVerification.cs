#if DEBUG
using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
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
            checks["ui_dll_sha256"]=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location)));
            // Measure readiness and idle before QA screenshots/navigation add
            // their deliberate animation wait and raster work to the timeline.
            if(scenario.TryGetProperty("idle_seconds",out var idle))
            {
                await Wait(()=>vm.AssetsReady,TimeSpan.FromSeconds(45));
                File.WriteAllText(Path.Combine(root,"performance-ready.json"),JsonSerializer.Serialize(new{ui_pid=Environment.ProcessId,control_pid=vm.BackendProcessId,window_ready_ms=window.WindowReadyMs,api_ready_ms=checks["api_ready_ms"],resources_ready_ms=(DateTime.UtcNow-Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds,idle_started_utc=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0}));
                await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(idle.GetInt32(),1,360)));
                File.WriteAllText(Path.Combine(root,"performance-idle-finished.json"),JsonSerializer.Serialize(new{idle_finished_utc=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0}));
            }
            await Capture(window,root,"01-workbench.png");
            if(!vm.Ready)throw new InvalidOperationException("后台尚未就绪："+vm.Notice);
            var workbench=Descendants(window).OfType<WorkbenchPage>().Single();
            checks["normal_layout"]=VerifyWorkbench(window,workbench);
            var entrance=(FrameworkElement)workbench.FindName("WorkbenchLayout");
            checks["component_library"]=typeof(Wpf.Ui.Controls.Card).Assembly.FullName!;
            checks["motion_library"]=typeof(XamlFlair.Animations).Assembly.FullName!;
            checks["system_client_area_animation"]=SystemParameters.ClientAreaAnimation;
            checks["library_motion_attached"]=XamlFlair.Animations.GetPrimary(entrance)!=null;
            checks["custom_application_styles"]=Application.Current.Resources.Values.OfType<Style>().Count();
            if((XamlFlair.Animations.GetPrimary(entrance)!=null)!=(vm.Appearance.EntranceAnimation!=null))throw new InvalidOperationException("动效库未按偏好连接到实际视图。");
            var originalTheme=vm.Appearance.ThemeChoice;var originalMotion=vm.Appearance.ReduceMotion;
            vm.Appearance.ThemeChoice=vm.Appearance.Themes[1];await Capture(window,root,"01b-workbench-dark.png");
            window.ShowPage(typeof(GlossaryPage));await Capture(window,root,"01c-glossary-dark.png");
            window.ShowPage(typeof(WorkbenchPage));await Task.Delay(20);
            LibraryMotion.Replay(entrance,vm.Appearance);
            await Task.Delay(30);
            checks["library_motion_probe"]=new{loaded=entrance.IsLoaded,opacity=entrance.Opacity,settings=XamlFlair.Animations.GetPrimary(entrance)!=null,enabled=vm.Appearance.EntranceAnimation!=null};
            checks["library_fade_has_actual_opacity_clock"]=DependencyPropertyHelper.GetValueSource(entrance,UIElement.OpacityProperty).IsAnimated;
            if(vm.Appearance.EntranceAnimation!=null&&!(bool)checks["library_fade_has_actual_opacity_clock"])throw new InvalidOperationException("动效库没有实际驱动页面透明度。");
            vm.Appearance.ReduceMotion=true;await Task.Delay(100);
            checks["reduced_motion_detaches_library_animation"]=XamlFlair.Animations.GetPrimary(entrance)==null;
            checks["reduced_motion_clears_actual_opacity_clock"]=!DependencyPropertyHelper.GetValueSource(entrance,UIElement.OpacityProperty).IsAnimated&&entrance.Opacity==1;
            using(var restored=new DesktopAppearance())
            {
                restored.Load(vm.DataDirectory);
                checks["appearance_roundtrip"]=restored.ThemeChoice?.Code=="dark"&&restored.ReduceMotion&&restored.EntranceAnimation==null;
            }
            if(!(bool)checks["appearance_roundtrip"]||!(bool)checks["reduced_motion_detaches_library_animation"]||!(bool)checks["reduced_motion_clears_actual_opacity_clock"])throw new InvalidOperationException("外观或减少动效设置未正确恢复。");
            vm.Appearance.ThemeChoice=originalTheme;vm.Appearance.ReduceMotion=originalMotion;
            LibraryMotion.Replay(entrance,vm.Appearance);await Task.Delay(300);
            checks["finite_fade_releases_opacity_clock"]=!DependencyPropertyHelper.GetValueSource(entrance,UIElement.OpacityProperty).IsAnimated&&entrance.Opacity==1;
            window.ShowPage(typeof(TasksPage));await Task.Delay(50);window.ShowPage(typeof(WorkbenchPage));await Task.Delay(300);
            checks["cached_page_reentry_visible"]=entrance.IsLoaded&&entrance.Opacity==1&&!DependencyPropertyHelper.GetValueSource(entrance,UIElement.OpacityProperty).IsAnimated;
            if(!(bool)checks["finite_fade_releases_opacity_clock"]||!(bool)checks["cached_page_reentry_visible"])throw new InvalidOperationException("页面淡入没有释放属性，或重新进入后不可见。");
            var probes=Path.Combine(vm.DataDirectory,"desktop","appearance-probes-"+Guid.NewGuid().ToString("N"));
            var probeDirectory=Path.Combine(probes,"desktop");Directory.CreateDirectory(probeDirectory);
            var malformedPassed=true;
            using(var appearance=new DesktopAppearance())
            {
                foreach(var bad in new[]{"null","[]","\"wrong\"","{invalid"})
                {
                    File.WriteAllText(Path.Combine(probeDirectory,"appearance.json"),"{\"theme\":\"dark\",\"reduce_motion\":true}");appearance.Load(probes);
                    File.WriteAllText(Path.Combine(probeDirectory,"appearance.json"),bad);appearance.Load(probes);
                    malformedPassed&=appearance.ThemeChoice?.Code=="light"&&!appearance.ReduceMotion;
                }
            }
            checks["malformed_appearance_isolated_from_backend"]=malformedPassed&&vm.Ready;
            if(!malformedPassed)throw new InvalidOperationException("损坏外观配置没有恢复默认。");
            if(scenario.TryGetProperty("appearance_fixture_home",out var fixtureValue))
            {
                var fixture=Path.GetFullPath(fixtureValue.GetString()!);var local=Path.GetFullPath(Path.Combine(Environment.GetEnvironmentVariable("PDF2ZH_APP_ROOT")!,".local"))+Path.DirectorySeparatorChar;
                if(!fixture.StartsWith(local,StringComparison.OrdinalIgnoreCase)||!File.Exists(Path.Combine(fixture,"owned-appearance-fixture.txt")))throw new InvalidOperationException("外观路径夹具必须属于本项目。");
                var link=Path.Combine(fixture,"desktop");var target=new DirectoryInfo(link).ResolveLinkTarget(true)?.FullName;
                if(target==null||!target.StartsWith(local,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("外观路径夹具目标必须属于本项目。");
                var sentinel=Path.Combine(target,"appearance.json");var before=File.ReadAllBytes(sentinel);var warnings=0;
                using(var appearance=new DesktopAppearance())
                {
                    appearance.SaveFailed+=_=>warnings++;appearance.Load(fixture);
                    var readRefused=warnings>0&&appearance.ThemeChoice?.Code=="light"&&!appearance.ReduceMotion;
                    appearance.ThemeChoice=appearance.Themes[1];
                    checks["appearance_reparse_read_and_write_refused"]=readRefused&&warnings>=2&&before.SequenceEqual(File.ReadAllBytes(sentinel));
                }
                if(!(bool)checks["appearance_reparse_read_and_write_refused"])throw new InvalidOperationException("外观路径夹具未被拒绝。");
            }
            vm.Appearance.Load(vm.DataDirectory);
            window.ShowPage(typeof(GlossaryPage));await Capture(window,root,"01d-glossary-light.png");
            window.ShowPage(typeof(SettingsPage)); await Capture(window,root,"02-settings.png");
            var settings=Descendants(window).OfType<SettingsPage>().Single();var key=(Wpf.Ui.Controls.PasswordBox)settings.FindName("ApiKey");
            var qps=vm.Qps;key.Password="local-fixture-only";vm.Qps="0";await vm.SaveSettingsCommand.ExecuteAsync(null);
            checks["failed_save_retains_key_draft"]=key.Password.Length>0;
            vm.Qps=qps;await vm.SaveSettingsCommand.ExecuteAsync(null);
            checks["all_save_paths_clear_key_after_success"]=key.Password.Length==0&&ReferenceEquals(((Wpf.Ui.Controls.Button)window.FindName("TopSaveButton")).Command,vm.SaveSettingsCommand);
            if(!(bool)checks["failed_save_retains_key_draft"]||!(bool)checks["all_save_paths_clear_key_after_success"])throw new InvalidOperationException("共享保存命令未正确处理密钥草稿。");
            window.ShowSettingsStorage(true);await Capture(window,root,"02b-save-directory.png");window.ShowSettingsStorage(false);
            window.ShowPage(typeof(TasksPage)); await Capture(window,root,"03-queue.png");
            if(scenario.TryGetProperty("layout_sample",out var layoutSample))
            {
                var samplePath=Path.GetFullPath(layoutSample.GetString()!);
                checks["layout_sample_sha256"]=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(samplePath)));
                var width=window.ActualWidth;var height=window.ActualHeight;
                window.ShowPage(typeof(WorkbenchPage));await vm.ImportAsync(Enumerable.Repeat(samplePath,4));
                if(vm.Files.Count!=4)throw new InvalidOperationException("多文件待提交夹具未完成四次实际上传。");
                window.Width=980;window.Height=680;await workbench.VerifyPreviewAsync(1,false);await Capture(window,root,"04a-four-pending-documents.png");
                checks["four_pending_compact_layout"]=VerifyWorkbench(window,workbench);
                vm.Files.Clear();vm.SelectedFile=null;window.Width=width;window.Height=height;
                vm.SelectedTask=vm.Store.Tasks.FirstOrDefault(x=>x.Status=="done");
                if(vm.SelectedTask==null)throw new InvalidOperationException("缺少真实已完成任务，不能验证译文视图。");
                await workbench.VerifyPreviewAsync(2,true);await Capture(window,root,"04b-actual-translated-page-two.png");
                checks["actual_translated_view_page_two"]=true;
            }
            if(!vm.Ready) throw new InvalidOperationException("后台尚未就绪："+vm.Notice);
            if(scenario.TryGetProperty("controls_only",out var controls)&&controls.GetBoolean())
            {
                var originalSource=vm.SourceLanguage;var originalTarget=vm.TargetLanguage;var originalAuto=vm.AutoCheckUpdates;
                vm.TargetLanguage=LanguageChoices.Resolve(vm.Languages,"fa");vm.AutoCheckUpdates=false;
                await vm.SaveSettingsCommand.ExecuteAsync(null);
                checks["uncommon_language_readback"]=vm.TargetLanguage?.Code=="fa";
                checks["auto_update_opt_out_readback"]=!vm.AutoCheckUpdates;
                if(vm.TargetLanguage?.Code!="fa"||vm.AutoCheckUpdates)throw new InvalidOperationException("偏好读回错误："+vm.Notice);
                vm.SourceLanguage=originalSource;vm.TargetLanguage=originalTarget;vm.AutoCheckUpdates=originalAuto;await vm.SaveSettingsCommand.ExecuteAsync(null);
                checks["missing_update_installer_keeps_service"]=await vm.VerifyMissingInstallerKeepsService();
                if(!(bool)checks["missing_update_installer_keeps_service"])throw new InvalidOperationException("更新失败未保留后台服务");
                window.ShowPage(typeof(SettingsPage));window.ShowSettingsStorage(true);await Capture(window,root,"11-update-recovery-and-saving.png");window.ShowSettingsStorage(false);
                vm.SelectedTask=vm.Store.Tasks.FirstOrDefault(x=>x.Status=="done"&&x.SavedPaths.Length>0);
                window.ShowPage(typeof(ResultsPage));await Capture(window,root,"12-restored-results.png");
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
                if(translated is null||translated.Pages<2||translated.Page!=2)throw new InvalidOperationException("译文预览页数或翻页读取错误");
                checks["translated_preview_page_count"]=translated.Pages;
                checks["missing_update_installer_keeps_service"]=await vm.VerifyMissingInstallerKeepsService();
                if(!(bool)checks["missing_update_installer_keeps_service"])throw new InvalidOperationException("更新启动失败后后台未保留");
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
                checks["result_version_cards"]=Descendants(window).OfType<ItemsControl>().Any(x=>x.ItemsSource is IReadOnlyList<SavedOutput> outputs&&outputs.Count==4);
                if(!(bool)checks["result_version_cards"])throw new InvalidOperationException("输出页未展示四个实际保存版本。");
                vm.Appearance.ThemeChoice=vm.Appearance.Themes[1];await Capture(window,root,"06b-results-dark.png");
                vm.Appearance.ThemeChoice=vm.Appearance.Themes[0];
                window.ShowPage(typeof(SettingsPage));await Capture(window,root,"07-effective-settings.png");
                window.ShowSettingsStorage(true);await Capture(window,root,"07b-save-directory.png");window.ShowSettingsStorage(false);
            }
            window.Width=980;window.Height=680;window.ShowPage(typeof(WorkbenchPage));await Capture(window,root,"08-compact-980.png");
            checks["compact_layout"]=VerifyWorkbench(window,workbench);
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
    private static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for(var i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++)
        {
            var child=VisualTreeHelper.GetChild(parent,i);yield return child;
            foreach(var nested in Descendants(child))yield return nested;
        }
    }
    private static object VerifyWorkbench(MainWindow window,WorkbenchPage page)
    {
        var bounds=new Dictionary<string,object>();
        foreach(var name in new[]{"SubmitButton","SourceLanguageInput","TargetLanguageInput"})
        {
            var element=(FrameworkElement)page.FindName(name);
            var point=element.TransformToAncestor(window).Transform(new Point());
            var rect=new Rect(point,new Size(element.ActualWidth,element.ActualHeight));
            var clip=new Rect(0,0,window.ActualWidth,window.ActualHeight);
            for(var ancestor=VisualTreeHelper.GetParent(element);ancestor!=null;ancestor=VisualTreeHelper.GetParent(ancestor))
                if(ancestor is ScrollViewer scroll){clip.Intersect(new Rect(scroll.TransformToAncestor(window).Transform(new Point()),new Size(scroll.ActualWidth,scroll.ActualHeight)));break;}
            if(!element.IsVisible||rect.Width<20||rect.Height<20||!clip.Contains(rect))throw new InvalidOperationException(name+" 在当前窗口中不可见或被裁切。");
            bounds[name]=new{x=rect.X,y=rect.Y,width=rect.Width,height=rect.Height};
        }
        var options=(FrameworkElement)page.FindName("FileOptionsPane");var preview=(FrameworkElement)page.FindName("PreviewPane");
        if(options.TransformToAncestor(window).Transform(new Point()).X>=preview.TransformToAncestor(window).Transform(new Point()).X)throw new InvalidOperationException("未保持左参数、右预览。");
        if(window.Content is not Panel panel||panel.Background is not SolidColorBrush brush||brush.Color.A!=255)throw new InvalidOperationException("窗口根背景不是组件库的不透明主题画刷。");
        return bounds;
    }
    private static async Task Capture(MainWindow window,string root,string name,double scale=1)
    {
        // NavigationView transitions can still be fading at 180 ms. Capture
        // after transition completion and a fresh layout/render pass.
        await Task.Delay(750);window.UpdateLayout();await window.Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);
        var bitmap=new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth*scale),(int)Math.Ceiling(window.ActualHeight*scale),96*scale,96*scale,PixelFormats.Pbgra32);
        bitmap.Render(window);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output=File.Create(Path.Combine(root,name));encoder.Save(output);
    }
}
#endif
