using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace PDFMathTranslate.Desktop;
public partial class SettingsPage : Page
{
    private readonly WorkbenchViewModel vm;
    public SettingsPage(WorkbenchViewModel vm) {this.vm=vm;InitializeComponent();DataContext=vm;}
    private void KeyChanged(object sender,RoutedEventArgs e)=>vm.NewApiKey=ApiKey.Password;
    private void ChooseFolder(object sender,RoutedEventArgs e){var dialog=new OpenFolderDialog {Title="选择默认保存目录"};if(dialog.ShowDialog()==true)vm.SaveDirectory=dialog.FolderName;}
    private async void SaveClicked(object sender,RoutedEventArgs e){await Task.Yield(); if(vm.SaveSettingsCommand.ExecutionTask is Task task) await task; ApiKey.Clear();}
}
