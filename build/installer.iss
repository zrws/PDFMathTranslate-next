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
#ifndef InstallerOutputDir
  #define InstallerOutputDir "..\dist"
#endif

#ifndef AppGuid
  #define AppGuid "{{7C1F9A3E-52B4-4D6E-9F0A-1B2C3D4E5F60}"
#endif
#ifndef AppGroup
  #define AppGroup "PDFMathTranslate"
#endif

[Setup]
AppId={#AppGuid}
AppName=PDFMathTranslate
AppVersion={#AppVersion}
AppVerName=PDFMathTranslate {#AppVersion}
AppPublisher=PDFMathTranslate-next
AppPublisherURL=https://github.com/zrws/PDFMathTranslate-next
AppSupportURL=https://github.com/zrws/PDFMathTranslate-next/issues
AppUpdatesURL=https://github.com/zrws/PDFMathTranslate-next/releases/latest
DefaultDirName={autopf}\PDFMathTranslate
DefaultGroupName={#AppGroup}
UninstallDisplayName=PDFMathTranslate {#AppVersion}
UninstallDisplayIcon={app}\PDFMathTranslate.exe
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; 始终显示安装目录页，让用户可以确认或更改安装路径。
DisableDirPage=no
DisableProgramGroupPage=no
AllowNoIcons=yes
OutputDir={#InstallerOutputDir}
OutputBaseFilename=PDFMathTranslate-Setup-{#AppVersion}
SetupIconFile=..\launcher\Assets\app.ico
Compression=lzma2/normal
SolidCompression=no
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no
AppMutex=Global\PDFMathTranslateNextSingleInstance

[Languages]
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[Messages]
; 覆盖产品专用文案；通用安装、错误和卸载提示由官方简体中文语言包提供。
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
Name: "startmenu"; Description: "创建开始菜单快捷方式"; GroupDescription: "快捷方式："

[Files]
; 精简便携运行环境（新界面、单套 Python、运行依赖和 version.json）
Source: "{#PayloadRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#PayloadRoot}\owned-files.tsv"; Flags: dontcopy

[Icons]
Name: "{group}\PDFMathTranslate"; Filename: "{app}\PDFMathTranslate.exe"; Tasks: startmenu
Name: "{group}\卸载 PDFMathTranslate"; Filename: "{uninstallexe}"; Tasks: startmenu
Name: "{autodesktop}\{#AppGroup}"; Filename: "{app}\PDFMathTranslate.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\PDFMathTranslate.exe"; Description: "{cm:LaunchProgram,PDFMathTranslate}"; Flags: nowait postinstall skipifsilent

[Code]
function GetFileAttributesW(Name: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function NativeLastError(): LongWord;
  external 'GetLastError@kernel32.dll stdcall';

// Pascal Script overload resolution can select the ANSI Pos overload for a
// literal needle. Keep indices in the same Unicode character units as Copy.
function UnicodePos(const Needle, Value: String): Integer;
var I: Integer;
begin
  Result:=0;
  for I:=1 to Length(Value)-Length(Needle)+1 do
    if Copy(Value,I,Length(Needle))=Needle then begin Result:=I;exit;end;
end;

function SafeOwnedPath(RelativeName: String; AllowMissing: Boolean): Boolean;
var Candidate, Root, FirstPart, Remaining, Part, Parent, Leaf: String; Attr, ErrorCode: LongWord; Separator: Integer;
begin
  Result := False;
  if (RelativeName='') or (UnicodePos('..',RelativeName)>0) or
     (UnicodePos(':',RelativeName)>0) or (Copy(RelativeName,1,1)='\') or
     (UnicodePos('/',RelativeName)>0) then exit;
  Remaining:=RelativeName;
  while Remaining<>'' do begin
    Separator:=UnicodePos('\',Remaining);
    if Separator=0 then begin Part:=Remaining; Remaining:=''; end
    else begin Part:=Copy(Remaining,1,Separator-1);Delete(Remaining,1,Separator);end;
    if (Part='') or (Part='.') or (Trim(Part)<>Part) or
       (Copy(Part,Length(Part),1)='.') or (UnicodePos('~',Part)>0) then exit;
  end;
  Separator:=UnicodePos('\',RelativeName);
  if Separator=0 then FirstPart:=Lowercase(RelativeName)
  else FirstPart:=Lowercase(Copy(RelativeName,1,Separator-1));
  if (FirstPart='home') or (FirstPart='outputs') or (FirstPart='pdf2zh_files') or
     (FirstPart='logs') or (FirstPart='config') or (FirstPart='cache') or
     (FirstPart='.cache') or (FirstPart='.config') or (FirstPart='downloads') then exit;
  Root := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  Candidate := Root+'\'+RelativeName;Leaf:=Candidate;
  // Never traverse a junction/symlink installed or changed by another writer.
  while Candidate<>'' do begin
    Attr := GetFileAttributesW(Candidate);
    if Attr=$FFFFFFFF then begin
      ErrorCode:=NativeLastError();
      if (not AllowMissing) or ((ErrorCode<>2) and (ErrorCode<>3)) then exit;
    end else begin
      if (Attr and $400)<>0 then exit;
      if (Candidate<>Leaf) and ((Attr and $10)=0) then exit;
      if (Candidate=Leaf) and ((Attr and $10)<>0) then exit;
    end;
    Parent:=ExtractFileDir(Candidate);
    if Parent=Candidate then break;
    Candidate:=Parent;
  end;
  Result := True;
end;
// Only obsolete, hash-matching files in our previous ownership list may be
// removed on upgrade. Unknown and modified files, home and outputs survive.
procedure RemoveObsoleteOwnedFiles();
var OldLines, NewLines: TArrayOfString; I, J, P: Integer;
    RelativeName, OldHash, Candidate: String; StillOwned: Boolean; NewNames: TStringList;
begin
  if not LoadStringsFromFile(ExpandConstant('{app}\owned-files.tsv'), OldLines) then exit;
  ExtractTemporaryFile('owned-files.tsv');
  if not LoadStringsFromFile(ExpandConstant('{tmp}\owned-files.tsv'), NewLines) then exit;
  NewNames:=TStringList.Create;
  try
  NewNames.CaseSensitive:=False;
  NewNames.Sorted:=True;
  NewNames.Duplicates:=dupIgnore;
  for J:=0 to GetArrayLength(NewLines)-1 do begin
    P:=UnicodePos('|',NewLines[J]);
    if P>1 then NewNames.Add(Copy(NewLines[J],1,P-1));
  end;
  for I := 0 to GetArrayLength(OldLines)-1 do begin
    P := UnicodePos('|', OldLines[I]);
    if P > 1 then begin
      RelativeName := Copy(OldLines[I], 1, P-1);
      OldHash := Copy(OldLines[I], P+1, MaxInt);
      // Fail closed on paths not produced by the builder.
      if SafeOwnedPath(RelativeName,False) then begin
        StillOwned := NewNames.Find(RelativeName,J);
        Candidate := ExpandConstant('{app}\')+RelativeName;
        if (not StillOwned) and FileExists(Candidate) and
           (CompareText(GetSHA256OfFile(Candidate),OldHash)=0) then begin
          if not DeleteFile(Candidate) then Log('保留无法删除的旧程序文件：'+RelativeName);
        end;
      end;
    end;
  end;
  finally NewNames.Free; end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Lines: TArrayOfString; I, P: Integer; RelativeName, Candidate, Parent: String;
begin
  if CurUninstallStep<>usUninstall then exit;
  if not LoadStringsFromFile(ExpandConstant('{app}\owned-files.tsv'),Lines) then exit;
  for I:=0 to GetArrayLength(Lines)-1 do begin
    P:=UnicodePos('|',Lines[I]);
    if P>1 then begin
      RelativeName:=Copy(Lines[I],1,P-1);
      if SafeOwnedPath(RelativeName,False) then begin
        Candidate:=ExpandConstant('{app}\')+RelativeName;
        if FileExists(Candidate) and (CompareText(GetSHA256OfFile(Candidate),Copy(Lines[I],P+1,MaxInt))=0) then begin
          if DeleteFile(Candidate) then begin
            Parent:=ExtractFileDir(Candidate);
            while Length(Parent)>Length(ExpandConstant('{app}')) do begin
              if not RemoveDir(Parent) then break;
              Parent:=ExtractFileDir(Parent);
            end;
          end else Log('保留无法删除的程序文件：'+RelativeName);
        end else Log('保留内容已修改或不存在的程序文件：'+RelativeName);
      end else Log('保留路径不受许可的程序文件：'+RelativeName);
    end;
  end;
  DeleteFile(ExpandConstant('{app}\owned-files.tsv'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep=ssInstall then RemoveObsoleteOwnedFiles();
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Lines: TArrayOfString; I, P: Integer;
begin
  Result:='';
  if not SafeOwnedPath('owned-files.tsv',True) or not SafeOwnedPath('unins000.exe',True) or not SafeOwnedPath('unins000.dat',True) then begin
    Result:='现有安装元数据路径不受许可，请更换目录。';exit;
  end;
  ExtractTemporaryFile('owned-files.tsv');
  if not LoadStringsFromFile(ExpandConstant('{tmp}\owned-files.tsv'),Lines) then begin
    Result:='无法读取程序文件清单，请重新下载安装包。';exit;
  end;
  if GetArrayLength(Lines)=0 then begin Result:='安装文件清单为空，已停止安装。';exit;end;
  for I:=0 to GetArrayLength(Lines)-1 do begin
    P:=UnicodePos('|',Lines[I]);
    if (P<=1) or not SafeOwnedPath(Copy(Lines[I],1,P-1),True) then begin
      Result:='安装路径含不可确认的目录、链接或不受许可的文件，请更换目录后重试。';exit;
    end;
  end;
end;
