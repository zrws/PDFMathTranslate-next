using System.Windows;
using System.Text.Json;

namespace PDFMathTranslate.Desktop;

public partial class App : Application
{
    private Mutex? instance;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
#if DEBUG
        // Explicit project-owned development profile; never read in Release.
        var profile=Path.Combine(AppContext.BaseDirectory,"development-run.json");
        if(File.Exists(profile))
        {
            using var config=JsonDocument.Parse(File.ReadAllText(profile));
            foreach(var key in new[]{"PDF2ZH_APP_ROOT","PDF2ZH_RUNTIME_ROOT","PDF2ZH_SOURCE_ROOT","PDF2ZH_HOME"})
                if(config.RootElement.TryGetProperty(key,out var value)) Environment.SetEnvironmentVariable(key,value.GetString(),EnvironmentVariableTarget.Process);
        }
#endif
        instance = new Mutex(true, @"Global\PDFMathTranslateNextSingleInstance", out var first);
        if (!first)
        {
            MessageBox.Show("PDFMathTranslate 已在运行，请切换到已有窗口。", "PDFMathTranslate");
            Shutdown(); return;
        }
        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show("操作未完成，请重试。" + Environment.NewLine + args.Exception.Message, "PDFMathTranslate");
            args.Handled = true;
        };
        MainWindow = new MainWindow();
        MainWindow.Show();
    }
    protected override void OnExit(ExitEventArgs e) { instance?.Dispose(); base.OnExit(e); }
}
