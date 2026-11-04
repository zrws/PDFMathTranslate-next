using System.ComponentModel;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Wpf.Ui.Appearance;
using XamlFlair;

namespace PDFMathTranslate.Desktop;

// WPF UI owns control templates, theme brushes and states. XamlFlair owns
// finite entrances; the application supplies no Storyboards or templates.
public partial class DesktopAppearance : ObservableObject, IDisposable
{
    public Choice[] Themes { get; } = [new("light", "浅色"), new("dark", "深色"), new("system", "跟随系统")];
    [ObservableProperty] private Choice? themeChoice;
    [ObservableProperty] private bool reduceMotion;
    private readonly AnimationSettings entrance = new() { Kind=AnimationKind.FadeFrom, Opacity=0, Duration=180, Event="None" };
    private string? preferencePath;
    private bool loading;
    private bool preferencesLoaded;
    private bool disposed;
    public event Action<string>? SaveFailed;
    public AnimationSettings? EntranceAnimation => !preferencesLoaded || ReduceMotion || !SystemParameters.ClientAreaAnimation ? null : entrance;
    public string ThemeAction => ApplicationThemeManager.GetAppTheme()==ApplicationTheme.Dark ? "切换浅色" : "切换深色";
    public DesktopAppearance()
    {
        loading=true;ThemeChoice=Themes[0];loading=false;
        SystemParameters.StaticPropertyChanged+=SystemPreferenceChanged;
        Microsoft.Win32.SystemEvents.UserPreferenceChanged+=UserPreferenceChanged;
    }
    public void Load(string ownedHome)
    {
        if(!Path.IsPathFullyQualified(ownedHome))throw new ArgumentException("外观偏好需要已确认的应用数据目录。",nameof(ownedHome));
        preferencePath=Path.Combine(ownedHome,"desktop","appearance.json");
        loading=true;
        ThemeChoice=Themes[0];ReduceMotion=false;
        try
        {
            CheckPreferencePath();
            if(File.Exists(preferencePath))
            {
                if(new FileInfo(preferencePath).Length>65536)throw new IOException("外观配置过大。");
                using var doc=JsonDocument.Parse(File.ReadAllText(preferencePath));
                if(doc.RootElement.ValueKind!=JsonValueKind.Object)throw new JsonException("外观偏好必须是对象。");
                if(doc.RootElement.TryGetProperty("theme",out var theme)&&theme.ValueKind==JsonValueKind.String)ThemeChoice=Themes.FirstOrDefault(x=>x.Code==theme.GetString())??Themes[0];
                if(doc.RootElement.TryGetProperty("reduce_motion",out var motion)&&motion.ValueKind is JsonValueKind.True or JsonValueKind.False)ReduceMotion=motion.GetBoolean();
            }
        }
        catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or JsonException) { SaveFailed?.Invoke("外观偏好暂不可读，已使用默认外观。"); }
        finally { loading=false;preferencesLoaded=true;ApplyTheme();OnPropertyChanged(nameof(EntranceAnimation)); }
    }
    partial void OnThemeChoiceChanged(Choice? value) { ApplyTheme();Save(); }
    partial void OnReduceMotionChanged(bool value) {OnPropertyChanged(nameof(EntranceAnimation));Save();}
    [RelayCommand] private void ToggleTheme() => ThemeChoice=ApplicationThemeManager.GetAppTheme()==ApplicationTheme.Dark?Themes[0]:Themes[1];
    private void ApplyTheme()
    {
        SystemThemeManager.UpdateSystemThemeCache();
        var theme=ThemeChoice?.Code switch {"dark"=>ApplicationTheme.Dark,"system"=>ApplicationThemeManager.GetSystemTheme()==SystemTheme.Dark?ApplicationTheme.Dark:ApplicationTheme.Light,_=>ApplicationTheme.Light};
        if(SystemParameters.HighContrast)theme=ApplicationTheme.HighContrast;
        // Ardot's primary token is slate-900 (#0f172a). The library accent
        // API generates its matching brushes and contrasting text.
        if(!SystemParameters.HighContrast)ApplicationAccentColorManager.Apply(theme==ApplicationTheme.Dark?Color.FromRgb(203,213,225):Color.FromRgb(15,23,42),theme,false);
        ApplicationThemeManager.Apply(theme,Wpf.Ui.Controls.WindowBackdropType.None,updateAccent:false);
        OnPropertyChanged(nameof(ThemeAction));
    }
    private void Save()
    {
        if(loading||preferencePath==null)return;
        var temporary=preferencePath+"."+Guid.NewGuid().ToString("N")+".tmp";
        try
        {
            CheckPreferencePath();
            Directory.CreateDirectory(Path.GetDirectoryName(preferencePath)!);
            CheckPreferencePath();
            File.WriteAllText(temporary,JsonSerializer.Serialize(new{theme=ThemeChoice?.Code??"light",reduce_motion=ReduceMotion}));
            File.Move(temporary,preferencePath,true);
        }
        catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) {SaveFailed?.Invoke("外观已切换，但偏好未能保存。请检查应用数据目录。");}
        finally {try{if(File.Exists(temporary))File.Delete(temporary);}catch(IOException){}catch(UnauthorizedAccessException){}}
    }
    private void SystemPreferenceChanged(object? sender,PropertyChangedEventArgs e)
    {
        if(disposed)return;
        if(e.PropertyName==nameof(SystemParameters.ClientAreaAnimation))OnPropertyChanged(nameof(EntranceAnimation));
        if(e.PropertyName==nameof(SystemParameters.HighContrast)||ThemeChoice?.Code=="system")ApplyTheme();
    }
    private void UserPreferenceChanged(object sender,Microsoft.Win32.UserPreferenceChangedEventArgs e)
    {
        var dispatcher=Application.Current?.Dispatcher;
        if(!disposed&&ThemeChoice?.Code=="system"&&dispatcher is {HasShutdownStarted:false})dispatcher.InvokeAsync(()=>{if(!disposed)ApplyTheme();});
    }
    private void CheckPreferencePath()
    {
        var directory=Path.GetDirectoryName(preferencePath!)!;
        foreach(var path in new[]{directory,preferencePath!})
        {
            try{if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("外观路径不能是重解析点。");}
            catch(FileNotFoundException){}catch(DirectoryNotFoundException){}
        }
    }
    public void Dispose()
    {
        disposed=true;
        SystemParameters.StaticPropertyChanged-=SystemPreferenceChanged;
        Microsoft.Win32.SystemEvents.UserPreferenceChanged-=UserPreferenceChanged;
    }
}
