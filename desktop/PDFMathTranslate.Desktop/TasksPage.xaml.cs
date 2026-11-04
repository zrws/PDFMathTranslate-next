using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;

namespace PDFMathTranslate.Desktop;

public partial class TasksPage : Page
{
    protected readonly WorkbenchViewModel Vm;
    public TasksPage(WorkbenchViewModel vm, bool resultsOnly=false)
    {
        Vm=vm;InitializeComponent();DataContext=vm;LibraryMotion.Attach(this,vm.Appearance);
        var view=new ListCollectionView(vm.Store.Tasks);
        view.SortDescriptions.Add(new SortDescription(nameof(TaskRow.Terminal),ListSortDirection.Ascending));
        if(resultsOnly){Heading.Text="翻译结果";view.Filter=x=>x is TaskRow row&&row.Status=="done";}
        TaskGrid.ItemsSource=view;
        vm.Store.PropertyChanged+=(_,e)=>{if(e.PropertyName==nameof(TaskStore.Summary))view.Refresh();};
    }
    private void OpenFolderClicked(object sender,RoutedEventArgs e)=>Open(false);
    private void TaskSelectionChanged(object sender,SelectionChangedEventArgs e)
    {if(IsLoaded&&IsVisible&&TaskGrid.SelectedItem is TaskRow row&&!ReferenceEquals(Vm.SelectedTask,row))Vm.SelectedTask=row;}
    private void OpenFileClicked(object sender,RoutedEventArgs e)=>Open(true);
    private void Open(bool file)
    {
        var path=Vm.SelectedTask?.SavedPaths.Split(Environment.NewLine,StringSplitOptions.RemoveEmptyEntries).FirstOrDefault(x=>x.EndsWith(".pdf",StringComparison.OrdinalIgnoreCase));
        if(path==null||!File.Exists(path)){Vm.Notice="请先保存结果。若文件已移动，请重新保存。";return;}
        if(file)Process.Start(new ProcessStartInfo(path){UseShellExecute=true});
        else {var info=new ProcessStartInfo("explorer.exe"){UseShellExecute=false};info.ArgumentList.Add("/select,"+path);Process.Start(info);}
    }
}
