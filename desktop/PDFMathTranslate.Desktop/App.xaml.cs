using System.Windows;
using System.Text.Json;

namespace PDFMathTranslate.Desktop;

public partial class App : Application
{
    private Mutex? instance;
#if DEBUG
    private string? verificationRoot;
    private void VerificationFailure(Exception error)
    {
        if(verificationRoot==null)return;
        Directory.CreateDirectory(verificationRoot);
        File.WriteAllText(Path.Combine(verificationRoot,"startup-error-"+Guid.NewGuid().ToString("N")+".json"),JsonSerializer.Serialize(new{type=error.GetType().FullName,message=error.Message,inner=error.InnerException?.Message,scope="owned DEBUG verification startup; not OS input"}));
    }
#endif
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
        var instanceName=@"Global\PDFMathTranslateNextSingleInstance";
#if DEBUG
        var verification=Array.IndexOf(e.Args,"--ui-test");
        if(verification>=0&&verification+1<e.Args.Length)
        {
            var appRoot=Environment.GetEnvironmentVariable("PDF2ZH_APP_ROOT")??throw new InvalidOperationException("测试缺少应用根");
            var scenarioPath=Path.GetFullPath(e.Args[verification+1]);
            var evidenceBase=Path.GetFullPath(Path.Combine(appRoot,"docs","verification","native-desktop"))+Path.DirectorySeparatorChar;
            var testHome=Path.GetFullPath(Environment.GetEnvironmentVariable("PDF2ZH_HOME")??"");
            if(!scenarioPath.StartsWith(evidenceBase,StringComparison.OrdinalIgnoreCase)||!testHome.StartsWith(Path.GetFullPath(Path.Combine(appRoot,".local"))+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("验证必须使用自有证据与独立 .local home");
            using var scenario=JsonDocument.Parse(File.ReadAllText(scenarioPath));var target=Path.GetFullPath(scenario.RootElement.GetProperty("output_root").GetString()!);
            if(!target.StartsWith(evidenceBase,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("测试输出越界");
            verificationRoot=target;
            instanceName=@"Local\PDFMathTranslateNextVerification-"+Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(testHome)))[..20];
        }
#endif
        instance = new Mutex(true, instanceName, out var first);
        if (!first)
        {
#if DEBUG
            if(verificationRoot!=null){VerificationFailure(new InvalidOperationException("本次独立测试 home 已有实例"));Shutdown(1);return;}
#endif
            MessageBox.Show("PDFMathTranslate 已在运行，请切换到已有窗口。", "PDFMathTranslate");
            Shutdown(); return;
        }
        DispatcherUnhandledException += (_, args) =>
        {
#if DEBUG
            if(verificationRoot!=null){VerificationFailure(args.Exception);args.Handled=true;Shutdown(1);return;}
#endif
            MessageBox.Show("操作未完成，请重试。" + Environment.NewLine + args.Exception.Message, "PDFMathTranslate");
            args.Handled = true;
        };
        try{MainWindow = new MainWindow();MainWindow.Show();}
        catch(Exception error)
        {
#if DEBUG
            if(verificationRoot!=null){VerificationFailure(error);Shutdown(1);return;}
#endif
            throw;
        }
    }
    protected override void OnExit(ExitEventArgs e) { instance?.Dispose(); base.OnExit(e); }
}
