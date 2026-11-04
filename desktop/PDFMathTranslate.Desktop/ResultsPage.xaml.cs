using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;

namespace PDFMathTranslate.Desktop;

public partial class ResultsPage : Page
{
    private readonly WorkbenchViewModel vm;
    public ResultsPage(WorkbenchViewModel vm)
    {
        this.vm=vm;InitializeComponent();DataContext=vm;LibraryMotion.Attach(this,vm.Appearance);
        var completed=new ListCollectionView(vm.Store.Tasks){Filter=x=>x is TaskRow row&&row.Terminal};
        completed.GroupDescriptions.Add(new PropertyGroupDescription(nameof(TaskRow.ArticleKey)));
        CompletedTasks.ItemsSource=completed;
        vm.Store.PropertyChanged+=(_,e)=>{if(e.PropertyName==nameof(TaskStore.Summary))completed.Refresh();};
        Loaded+=(_,_)=>{if(vm.SelectedTask?.Terminal!=true)vm.SelectedTask=completed.Cast<TaskRow>().FirstOrDefault();};
    }
    private void TaskSelectionChanged(object sender,SelectionChangedEventArgs e)
    {if(IsLoaded&&IsVisible&&CompletedTasks.SelectedItem is TaskRow row&&!ReferenceEquals(vm.SelectedTask,row))vm.SelectedTask=row;}
    private void OpenFileClicked(object sender,RoutedEventArgs e)=>Open(sender,false);
    private void ChooseExportFolder(object sender,RoutedEventArgs e)
    {var dialog=new Microsoft.Win32.OpenFolderDialog {Title="选择本次结果保存目录"};if(dialog.ShowDialog()==true){vm.ExportDirectory=dialog.FolderName;vm.ExportToSource=false;}}
    private void OpenFolderClicked(object sender,RoutedEventArgs e)=>Open(sender,true);
    private void Open(object sender,bool folder)
    {
        if(sender is not FrameworkElement element||element.Tag is not string path||!File.Exists(path)) {vm.Notice="文件已移动或尚未保存，请重新保存结果。";return;}
        if(folder){var info=new ProcessStartInfo("explorer.exe"){UseShellExecute=false};info.ArgumentList.Add("/select,"+path);Process.Start(info);}
        else if(Path.GetExtension(path).ToLowerInvariant() is ".pdf" or ".csv")Process.Start(new ProcessStartInfo(path){UseShellExecute=true});
    }
}
