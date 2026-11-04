using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace PDFMathTranslate.Desktop;

public partial class WorkbenchPage : Page
{
    private readonly WorkbenchViewModel vm;
    private CancellationTokenSource? render;
    private int page=1, count;
    public WorkbenchPage(WorkbenchViewModel vm)
    {
        this.vm=vm; InitializeComponent(); DataContext=vm;LibraryMotion.Attach(this,vm.Appearance);
        vm.SelectionChanged+=async ()=> {page=1; await RenderAsync();};
        InputBindings.Add(new KeyBinding(new CommunityToolkit.Mvvm.Input.RelayCommand(Import),Key.O,ModifierKeys.Control));
        Unloaded+=(_,_)=>render?.Cancel();
    }
    private void ImportClicked(object sender,RoutedEventArgs e)=>Import();
    private void HistoryClicked(object sender,RoutedEventArgs e)=>(Window.GetWindow(this) as MainWindow)?.ShowPage(typeof(TasksPage));
    private void SettingsClicked(object sender,RoutedEventArgs e)=>(Window.GetWindow(this) as MainWindow)?.ShowPage(typeof(SettingsPage));
    private void PreviewAreaChanged(object sender,SizeChangedEventArgs e)
    {if(PreviewIcon!=null)PreviewIcon.Visibility=e.NewSize.Height<120?Visibility.Collapsed:Visibility.Visible;}
    private async void Import() { var dialog=new OpenFileDialog {Filter="PDF 文档 (*.pdf)|*.pdf",Multiselect=true,Title="选择待翻译 PDF"}; if(dialog.ShowDialog()==true) await vm.ImportAsync(dialog.FileNames); }
    private async void FilesDropped(object sender,DragEventArgs e) { if(e.Data.GetData(DataFormats.FileDrop) is string[] files) await vm.ImportAsync(files); }
    private void TaskFolderClicked(object sender,RoutedEventArgs e) {var d=new OpenFolderDialog {Title="选择本次任务保存目录"};if(d.ShowDialog()==true) vm.TaskDirectory=d.FolderName;}
    private async void PreviousPage(object sender,RoutedEventArgs e) {page=Math.Max(1,page-1);await RenderAsync();}
    private async void NextPage(object sender,RoutedEventArgs e) {page=Math.Min(Math.Max(1,count),page+1);await RenderAsync();}
    private async void PageKeyDown(object sender,KeyEventArgs e) {if(e.Key==Key.Enter){if(int.TryParse(PageNumber.Text,out var n)) page=Math.Clamp(n,1,Math.Max(1,count));await RenderAsync();}}
    private async void PreviewModeChanged(object sender,RoutedEventArgs e) {if(!IsInitialized)return;page=1;await RenderAsync();}
    private async Task RenderAsync()
    {
        render?.Cancel();render?.Dispose();render=new CancellationTokenSource();var current=render;
        Preview.Source=null;PreviewPlaceholder.Visibility=Visibility.Visible;PreviewMessage.Text="正在读取预览…";
        try
        {
            var data=await vm.PreviewAsync(page,OutputPreview.IsChecked==true,current.Token);
            if(current.IsCancellationRequested)return;
            if(data==null){PreviewMessage.Text="导入 PDF 或选择已完成任务以预览。";return;}
            var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.DecodePixelWidth=1200;bitmap.StreamSource=new MemoryStream(data.Image);bitmap.EndInit();bitmap.Freeze();Preview.Source=bitmap;
            count=data.Pages;page=data.Page;
            PageNumber.Text=page.ToString();PageCount.Text=" / "+count;PreviewPlaceholder.Visibility=Visibility.Collapsed;
        }
        catch(OperationCanceledException) { }
        catch(Exception){if(!current.IsCancellationRequested)PreviewMessage.Text="预览暂不可用。请确认文件有效，或重新选择页面。翻译任务可继续操作。";}
    }
}
