# 第三方软件与许可

PDFMathTranslate-next 按仓库 LICENSE 分发。翻译与排版继续使用 BabelDOC 0.6.2（AGPL-3.0），补丁与源码在本仓库 build/patches/babeldoc 和 source 中提供。

桌面采用 .NET 10（MIT）、WPF UI 4.3.0（MIT）和 CommunityToolkit.Mvvm 8.4.2（MIT）；Python 3.12.13 使用 PSF 许可。NuGet 包许可、Python 各发行包的 LICENSE、COPYING 与 *.dist-info 许可随运行环境保留。完整依赖、版本及哈希见 build/dependency-locks/windows-py312.txt 与 desktop/*/packages.lock.json。

原生界面动效采用 XamlFlair.WPF 1.2.13（MIT），许可见 licenses/XamlFlair-LICENSE.txt；上游源码 https://github.com/XamlFlair/XamlFlair ，参考提交 cd5bd4a55d22001ebaef5a4643b408e60dba9810。随它运行的 System.Reactive 5.0.0（MIT）、Microsoft.Extensions.Logging.Abstractions 10.0.0（MIT）及 DependencyInjection.Abstractions 10.0.0（MIT）版本、包内容哈希及许可见 NuGet 锁和安装目录 licenses。应用显式锁定 Logging 10.0.0，避免使用 XamlFlair 的旧版传递默认值。SourceLink/Git 任务仅为传递的构建工具，不在应用中启动。

模型与字体不随安装包分发。应用显式下载 BabelDOC 的资源，资源名称、大小与内容哈希固定于 source/pdf2zh_next/desktop/assets.lock.json；对应资源的上游许可仍适用。

源码与构建说明：https://github.com/zrws/PDFMathTranslate-next
