# PDFMathTranslate-next 桌面版

在 [PDFMathTranslate-next](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next) 基础上二次开发的 **Windows 桌面版**：带安装程序、内嵌 Web 界面的原生窗口（WebView2），以及一套重新设计的界面。

> 上游项目采用 AGPL-3.0，本仓库同样遵循该协议（见 [`source/LICENSE`](source/LICENSE)）。翻译引擎、排版还原能力来自上游与 BabelDOC。

## 特性

**桌面外壳（`launcher/`，C# / .NET 8 + WebView2）**

- 原生窗口内嵌 Web 界面，不再是浏览器标签页
- 关闭浏览器痕迹：禁用右键菜单、开发者工具、缩放、浏览器快捷键、状态栏
- 下载静默保存到「下载」目录
- 单实例运行；退出时自动结束后端进程
- 启动时检查更新（GitHub Releases），提示后静默重装

**全新 Web 界面（`webui/`）**

- 5 个页面：翻译工作台 / 设置 / 任务队列 / 文档输出 / 术语表
- PDF 预览：PyMuPDF 实时渲染 + 翻页；翻译完成后可预览译文
- 任务：实时进度、失败重试、取消
- 术语表：上传 CSV、删除条目、下载自动提取的术语表
- 深色主题（跟随系统 / 浅色 / 深色）、组件化弹窗与 Toast 提示
- 设置：翻译服务、API Key、Base URL、模型、提示词、限流（QPS/RPM/并发）、译文主字体

**后端 API（`source/pdf2zh_next/http_api.py`，FastAPI）**

- 托管 `webui/` 静态界面，提供 `/api/settings`、`/api/files`、`/api/tasks`、`/api/glossary`、`/api/prefs`、预览与下载等接口
- 设置写入前先校验，非法值返回 400 且不落盘

**安装程序（`build/`，Inno Setup）**

- 可安装到任意目录；默认免管理员（`%LOCALAPPDATA%\Programs\PDFMathTranslate`），也可选择"为所有用户安装"装到 `Program Files`
- 中文安装向导；自带卸载程序
- 装在只读目录时，用户数据自动回退到 `%LOCALAPPDATA%\PDFMathTranslate`

## 安装

从 [Releases](https://github.com/zrws/PDFMathTranslate-next/releases) 下载 `PDFMathTranslate-Setup-<版本>.exe`：

```powershell
# 图形安装（向导中可选择安装位置）
.\PDFMathTranslate-Setup-2.9.0.exe

# 静默安装并指定目录
.\PDFMathTranslate-Setup-2.9.0.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="D:\Apps\PDFMathTranslate"
```

数据与配置：安装目录下的 `home\`（配置 `home\.config\pdf2zh\config.v3.toml`、日志 `logs\`、输出 `pdf2zh_files\`）。

## 从源码运行

需要便携 Python 运行时（`uv-python/`）与依赖（`uv-tools/`，发行包中提供；源码仓库不含）。

```powershell
# 新界面（桌面壳默认入口）
python start-webui.py --server-port 7860

# 上游 Gradio 旧界面（兼容保留）
python start-gui-direct.py --server-port 7860
```

浏览器打开 `http://127.0.0.1:7860`；桌面壳方式为双击 `PDFMathTranslate.exe`。

## 构建

```powershell
# 便携 EXE（只更新启动器）
powershell -ExecutionPolicy Bypass -File build-portable-exe.ps1

# 完整安装包 + 自动更新清单
powershell -ExecutionPolicy Bypass -File build\build-release.ps1
# 产物：dist\PDFMathTranslate-Setup-<版本>.exe、dist\latest.json
```

依赖：.NET 8 SDK、Inno Setup 6（`winget install JRSoftware.InnoSetup`）。应用图标可用 `build/generate-icon.ps1` 重新生成。

## 目录结构

```
source/                 Python 包与上游代码（pdf2zh_next）
launcher/               C# 桌面壳（WinForms + WebView2 + 更新器）
build/                  构建脚本与 Inno Setup 脚本
webui/                  Web 界面源码（HTML/CSS/JS，无构建步骤）
start-webui.py          新界面启动入口
start-gui-direct.py     上游 Gradio 界面启动入口
使用说明.md              中文使用说明（含安装版说明）
```

## 致谢

- [PDFMathTranslate-next](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next) —— 翻译引擎与原始项目
- [BabelDOC](https://github.com/funstory-ai/BabelDOC) —— PDF 排版解析与还原
- [Inno Setup](https://jrsoftware.org/isinfo.php) —— 安装程序
