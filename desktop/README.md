# Windows 原生桌面预览

默认发行入口是 `PDFMathTranslate.Desktop`：WPF、.NET 10、WPF UI 4.3.0、CommunityToolkit.Mvvm 8.4.2。Python/BabelDOC 保留翻译、排版与 CLI；默认窗口不加载浏览器或 Gradio。

构建工具全部可以放在项目外的个人工具目录。无需全局安装 SDK 或修改 PATH。SDK 精确版本见根目录 global.json，CPython 为 3.12.13，依赖安装使用 build/dependency-locks/windows-py312.txt 的哈希锁。先自行准备可信的 SDK、uv、完整 CPython 和 Inno Setup 6.7.1，然后在仓库根运行：

```powershell
./build/build-release.ps1 -DotnetExe '<本地 SDK>/dotnet.exe' -UvExe '<本地 uv>/uv.exe' -PythonRoot '<本地 CPython 完整目录>' -IsccExe '<本地 Inno>/ISCC.exe'
```

`-Offline` 要求依赖已经在本仓库 `.local/uv-cache` 中，不会临时联网补包。每轮创建新的洁净 venv 与 payload，验证哈希后应用三个 BabelDOC 补丁；原 Python 环境不修改。NuGet 以 packages.lock.json 锁定。默认预览频道不生成正式 latest.json，不自动发布、删除 dist、创建 tag 或 Release。构建报告、安装包与 payload 路径写入新的 `dist/native-*/build-report.json`。

安装包自带私有 .NET 10 与单套 Python，不带 SDK、模型、字体缓存或用户配置。首次使用需在「资源与设置」显式准备 BabelDOC 资源；也可由运维把经清单校验的离线资源放进应用数据目录的 `.cache/babeldoc`。默认 GPU 关闭，翻译任务并发为 1。

数据默认存于 `%LOCALAPPDATA%/PDFMathTranslate`；`portable.marker` 放在应用根目录时改用旁边的 home。测试可通过 PDF2ZH_HOME 指定独立目录。PDF2ZH_APP_ROOT、PDF2ZH_RUNTIME_ROOT、PDF2ZH_SOURCE_ROOT 用于明确的本地开发配置；Release 忽略 development-run.json。应用独占 home 的 writer lock，WPF 与显式旧入口不能同时写入。

旧 WebView 源码保留在 launcher，必须显式 `-LegacyWebView` 才走原构建流程；需另备 WebView2。其本地 HTTP 同样使用随机会话认证，WebView 仅给精确回环源附加认证头，直接浏览器访问会被拒绝。start-webui.py、Gradio 与 CLI 源码兼容入口仍保留，开发者单独运行时应使用自己的隔离 home；默认安装包不暴露它们。

显式旧入口构建可用 `-LegacyRuntimeRoot '<含 uv-tools/uv-python 的目录>'`、`-PythonRoot '<版本化 CPython>'` 和相同的本地 DotnetExe/IsccExe；preview/stable 元数据保持独立，preview 不生成正式 latest.json。已验证旧 .NET 编译、真实认证引导和占位端口拒绝，未运行旧 WebView GUI/完整旧安装器，不能把它们列为全部通过。

预览更新源关闭。未来稳定频道保留 Releases/latest.json、版本比较与 SHA256 校验；仓库没有既有数字签名验证，不把 SHA256 描述成发布者签名。测试只使用本地假 feed。安装/升级删除旧文件前检查拥有清单、哈希和路径，卸载保留未知/修改过的文件与数据目录；该检查不宣称抵抗恶意并发文件替换。

验收入口：tests/native/acceptance.py（真实 BabelDOC + 本地 LLM 夹具）、tests/native/performance.py、tests/native/installer.ps1、desktop/PDFMathTranslate.Tests。DEBUG 的 --ui-test 在真实运行的 WPF 视图内执行流程并渲染 PNG；它不等同于操作系统输入、文件对话框或跨屏 DPI 验收。当前证据与未验证项见 docs/NATIVE_DESKTOP_REVIEW_HANDOFF.md。
