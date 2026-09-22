; PDFMathTranslate Inno Setup 安装脚本
;
; 用法（通常由 build-release.ps1 调用）：
;   ISCC.exe /DAppVersion=2.9.0 /DPayloadRoot="..\dist\payload" installer.iss
;
; 设计要点：
;   - 默认 per-user 安装（{localappdata}\Programs），免 UAC，静默更新无需管理员；
;     高级用户仍可在向导中改到其他目录（如 Program Files）。
;   - 用户数据（home\ 下的配置与密钥）不在安装清单中，升级/卸载均不会覆盖或删除。
;   - 更新 = 整包重装：以 /SILENT 重新运行本安装器即可（升级时默认沿用原目录）。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef PayloadRoot
  #define PayloadRoot "..\dist\payload"
#endif

#define AppGuid "{{7C1F9A3E-52B4-4D6E-9F0A-1B2C3D4E5F60}"

[Setup]
AppId={#AppGuid}
AppName=PDFMathTranslate
AppVersion={#AppVersion}
AppVerName=PDFMathTranslate {#AppVersion}
AppPublisher=PDFMathTranslate-next
AppPublisherURL=https://github.com/PDFMathTranslate-next/PDFMathTranslate-next
AppSupportURL=https://github.com/PDFMathTranslate-next/PDFMathTranslate-next/issues
AppUpdatesURL=https://github.com/PDFMathTranslate-next/PDFMathTranslate-next/releases/latest
DefaultDirName={autopf}\PDFMathTranslate
DefaultGroupName=PDFMathTranslate
UninstallDisplayName=PDFMathTranslate {#AppVersion}
UninstallDisplayIcon={app}\PDFMathTranslate.exe
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=PDFMathTranslate-Setup-{#AppVersion}
SetupIconFile=..\launcher\Assets\app.ico
Compression=lzma2/normal
SolidCompression=no
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no

[Languages]
; 若放置了官方中文语言包（build\languages\ChineseSimplified.isl）则启用完整中文向导
#if FileExists(AddBackslash(SourcePath) + "languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
; 基础语言为英文，这里覆盖向导主要文案，使界面为中文（无需外部语言包）
SetupAppTitle=安装 - %1
SetupWindowTitle=安装 - %1
UninstallAppTitle=卸载 - %1
UninstallAppFullTitle=卸载 %1
WelcomeLabel1=欢迎使用 %1 安装向导
WelcomeLabel2=即将把 [name/ver] 安装到你的电脑。%n%n建议关闭其他应用程序后继续。
WizardSelectDir=选择安装位置
SelectDirDesc=要将 [name] 安装到哪里？
SelectDirLabel3=安装程序将把 [name] 安装到以下文件夹。
SelectDirBrowseLabel=点击“下一步”继续；如需更换目录，请点击“浏览”。
DiskSpaceGBLabel=至少需要 [gb] GB 可用磁盘空间。
DiskSpaceMBLabel=至少需要 [mb] MB 可用磁盘空间。
WizardSelectTasks=选择附加任务
SelectTasksDesc=还需要执行哪些附加任务？
SelectTasksLabel2=请选择安装 [name] 时要执行的附加任务，然后点击“下一步”。
WizardReady=准备安装
ReadyLabel1=安装程序已准备好在你的电脑上安装 [name]。
ReadyLabel2a=点击“安装”开始安装，或点击“上一步”检查或更改设置。
ReadyLabel2b=点击“安装”开始安装。
WizardInstalling=正在安装
InstallingLabel=正在安装 [name]，请稍候…
FinishedHeadingLabel=[name] 安装完成
FinishedLabelNoIcons=[name] 已安装完成。
FinishedLabel=[name] 已安装完成，可通过开始菜单或桌面图标启动。
ClickFinish=点击“完成”结束安装。
RunEntryExec=运行 %1
RunEntryShellExec=打开 %1
ButtonNext=下一步(&N) >
ButtonBack=< 上一步(&B)
ButtonInstall=安装(&I)
ButtonFinish=完成(&F)
ButtonCancel=取消
ButtonBrowse=浏览(&R)...
ButtonYes=是(&Y)
ButtonNo=否(&N)
ButtonOK=确定
ConfirmUninstall=确定要完全卸载 %1 及其所有组件吗？
UninstallStatusLabel=正在从电脑中移除 %1，请稍候…
UninstalledAll=%1 已成功卸载。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 完整便携运行环境（exe、start-gui-direct.py、bin、uv-python、uv-tools、version.json 等）
Source: "{#PayloadRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PDFMathTranslate"; Filename: "{app}\PDFMathTranslate.exe"
Name: "{group}\卸载 PDFMathTranslate"; Filename: "{uninstallexe}"
Name: "{autodesktop}\PDFMathTranslate"; Filename: "{app}\PDFMathTranslate.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\PDFMathTranslate.exe"; Description: "{cm:LaunchProgram,PDFMathTranslate}"; Flags: nowait postinstall skipifsilent

[Code]
var
  UpdateExitCode: Integer;

// WebView2 Evergreen 运行时（窗口界面依赖）：注册表探测 GUID {F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
function WebView2Installed(): Boolean;
begin
  Result :=
    RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
    RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
    RegKeyExists(HKEY_CURRENT_USER, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if not WebView2Installed() then
    begin
      if MsgBox(
        '未检测到 Microsoft WebView2 运行时，窗口界面需要它才能显示。'#13#10#13#10 +
        '是否现在打开官方下载页面进行安装？（安装完成后重新启动 PDFMathTranslate 即可）',
        mbConfirmation, MB_YESNO) = IDYES then
      begin
        ShellExec('open', 'https://aka.ms/webview2', '', '', SW_SHOWNORMAL, ewNoWait, UpdateExitCode);
      end;
    end;
  end;
end;
