using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;

namespace PDFMathTranslate.Desktop;
public partial class SettingsPage : Page
{
    private readonly WorkbenchViewModel vm;
    public SettingsPage(WorkbenchViewModel vm) {this.vm=vm;InitializeComponent();DataContext=vm;LibraryMotion.Attach(this,vm.Appearance);vm.SettingsSaved+=()=>ApiKey.Password="";}
    private void KeyChanged(object sender,RoutedEventArgs e)=>vm.NewApiKey=ApiKey.Password;
    internal void ScrollStorage(bool end)
    {
        if(!end){SettingsScroll.ScrollToTop();return;}
        SettingsScroll.UpdateLayout();
        var point=StorageSection.TransformToAncestor((Visual)SettingsScroll.Content).Transform(new Point());
        SettingsScroll.ScrollToVerticalOffset(point.Y);
    }
    private void ChooseFolder(object sender,RoutedEventArgs e){var dialog=new OpenFolderDialog {Title="选择默认保存目录"};if(dialog.ShowDialog()==true)vm.SaveDirectory=dialog.FolderName;}
}
