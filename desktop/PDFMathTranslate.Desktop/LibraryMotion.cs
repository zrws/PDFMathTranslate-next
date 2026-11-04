using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using CommunityToolkit.Mvvm.Input;
using XamlFlair;

namespace PDFMathTranslate.Desktop;

// XamlFlair generates the fade. Its stock Loaded subscription ends on unload,
// and null Primary does not remove an already running opacity clock. This
// adapter handles cached pages and promptly restores a usable visual state.
internal static class LibraryMotion
{
    internal static void Attach(Page page,DesktopAppearance appearance)
    {
        var root=(FrameworkElement)page.Content;
        void Changed(object? sender,PropertyChangedEventArgs e)
        {if(e.PropertyName==nameof(DesktopAppearance.EntranceAnimation)&&appearance.EntranceAnimation==null)Reset(root);}
        root.Loaded+=(_,_)=>{appearance.PropertyChanged+=Changed;Replay(root,appearance);};
        root.Unloaded+=(_,_)=>{appearance.PropertyChanged-=Changed;Reset(root);};
        Animations.SetPrimaryCompletionCommand(root,new RelayCommand(()=>Reset(root)));
    }
    internal static void Replay(FrameworkElement root,DesktopAppearance appearance)
    {
        Reset(root);
        if(appearance.EntranceAnimation==null||!root.IsLoaded)return;
        Animations.SetPrimaryBinding(root,false);
        Animations.SetPrimaryBinding(root,true);
    }
    private static void Reset(FrameworkElement root)
    {
        root.BeginAnimation(UIElement.OpacityProperty,null);
        root.Opacity=1;
    }
}
