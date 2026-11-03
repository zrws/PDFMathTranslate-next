using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using FluentWindow = Wpf.Ui.Controls.FluentWindow;

namespace PDFMathTranslate.Desktop;

public partial class MainWindow : FluentWindow
{
    public WorkbenchViewModel ViewModel { get; } = new();
    private readonly SettingsPage settingsPage;
    internal double WindowReadyMs {get;private set;}
#if DEBUG
    internal bool AutomatedClose {get;set;}
#endif
    public MainWindow()
    {
        InitializeComponent(); DataContext=ViewModel;
        settingsPage=new SettingsPage(ViewModel);
        var pages=new Dictionary<Type,object> { [typeof(WorkbenchPage)]=new WorkbenchPage(ViewModel),[typeof(TasksPage)]=new TasksPage(ViewModel),[typeof(ResultsPage)]=new ResultsPage(ViewModel),[typeof(SettingsPage)]=settingsPage,[typeof(GlossaryPage)]=new GlossaryPage(ViewModel) };
        foreach(var page in pages.Values.Cast<Page>()) page.SetBinding(FrameworkElement.HeightProperty,new Binding(nameof(ActualHeight)){Source=Navigation,Mode=BindingMode.OneWay});
        Navigation.SetServiceProvider(new PageProvider(pages));
        Loaded+=async (_,_)=> {
            WindowReadyMs=(DateTime.UtcNow-System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds;
            Navigation.Navigate(typeof(WorkbenchPage)); await ViewModel.InitializeAsync();
#if DEBUG
            var args=Environment.GetCommandLineArgs(); var index=Array.IndexOf(args,"--ui-test");
            if(index>=0 && index+1<args.Length) await NativeUiVerification.RunAsync(this,ViewModel,args[index+1]);
#endif
        };
        Closing+=OnClosing;
    }
    internal void ShowPage(Type page)=>Navigation.Navigate(page);
    internal void ShowSettingsStorage(bool end)=>settingsPage.ScrollStorage(end);
    private void OnClosing(object? sender,CancelEventArgs e)
    {
#if DEBUG
        if(AutomatedClose){ViewModel.Dispose();return;}
#endif
        if(ViewModel.Store.Tasks.Any(x=>!x.Terminal) && MessageBox.Show("仍有任务尚未完成。退出会中断翻译，是否退出？","退出 PDFMathTranslate",MessageBoxButton.YesNo,MessageBoxImage.Question)!=MessageBoxResult.Yes) { e.Cancel=true;return; }
        ViewModel.Dispose();
    }
    private sealed class PageProvider(Dictionary<Type,object> pages) : IServiceProvider { public object? GetService(Type type)=>pages.GetValueOrDefault(type); }
}
