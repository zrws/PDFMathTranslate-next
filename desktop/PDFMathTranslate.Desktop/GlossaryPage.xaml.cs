using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
namespace PDFMathTranslate.Desktop;
public partial class GlossaryPage : Page
{
    private readonly WorkbenchViewModel vm;
    public GlossaryPage(WorkbenchViewModel vm){this.vm=vm;InitializeComponent();DataContext=vm;Loaded+=async(_,_)=>await Refresh();}
    private async Task Refresh(){try{await vm.LoadGlossaryAsync();}catch(Exception){vm.Notice="无法读取术语表，请确认服务已就绪后刷新。";}}
    private async void RefreshClicked(object sender,RoutedEventArgs e)=>await Refresh();
    private async void ImportClicked(object sender,RoutedEventArgs e){var dialog=new OpenFileDialog{Filter="术语 CSV (*.csv)|*.csv",Title="导入术语表"};if(dialog.ShowDialog()==true)await vm.ImportGlossaryAsync(dialog.FileName);}
}
