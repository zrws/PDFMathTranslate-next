param([Parameter(Mandatory=$true)][string]$FirstInstaller,[Parameter(Mandatory=$true)][string]$UpgradeInstaller,[Parameter(Mandatory=$true)][string]$AppId,[Parameter(Mandatory=$true)][string]$Group,[Parameter(Mandatory=$true)][string]$EvidenceRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if($AppId -notmatch '^PDFMathTranslate-Codex-Test-[a-f0-9]+$' -or $Group -notmatch '^PDFMathTranslate-Codex-Test-[a-f0-9]+$'){throw '只允许独立的测试安装标识和快捷方式名称'}
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot)
if(Test-Path -LiteralPath $EvidenceRoot){throw '证据目录必须全新'}
if(!$EvidenceRoot.StartsWith((Join-Path $repo 'docs/verification/native-desktop/'),[StringComparison]::OrdinalIgnoreCase)){throw '证据路径越界'}
New-Item -ItemType Directory -Path $EvidenceRoot | Out-Null
$install=Join-Path $repo ('.local/安装 验证-'+[guid]::NewGuid().ToString('N').Substring(0,10))
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$AppId+'_is1'
if(Test-Path -LiteralPath $key){throw '测试注册项已存在，拒绝覆盖'}
$rows=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed,$Detail=$null){$rows.Add(@{case=$Name;passed=$Passed;detail=$Detail});if(!$Passed){throw $Name}}
function Run-Setup([string]$Exe,[string[]]$Arguments){$p=Start-Process -FilePath $Exe -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait;return $p.ExitCode}
$success=$false
try{
    $code=Run-Setup $FirstInstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$install+'"'),('/GROUP="'+$Group+'"'),'/TASKS=startmenu,desktopicon',('/LOG="'+(Join-Path $EvidenceRoot 'install.log')+'"'),('/SAVEINF="'+(Join-Path $EvidenceRoot 'install.inf')+'"'))
    Check '中文路径安装实际退出0' ($code -eq 0)
    $registration=Get-ItemProperty -LiteralPath $key
    $registration | Select-Object DisplayName,DisplayVersion,InstallLocation,UninstallString,QuietUninstallString,Publisher,EstimatedSize | ConvertTo-Json | Set-Content (Join-Path $EvidenceRoot 'registered-uninstall.json') -Encoding utf8
    Check '标准卸载发现信息完整' ($registration.DisplayName -like 'PDFMathTranslate*' -and $registration.DisplayVersion -eq '2.9.0' -and $registration.InstallLocation.TrimEnd('\') -eq $install.TrimEnd('\') -and $registration.UninstallString -and $registration.QuietUninstallString -and $registration.EstimatedSize -gt 0)
    Check '开始菜单快捷方式' (Test-Path -LiteralPath (Join-Path $env:APPDATA ('Microsoft/Windows/Start Menu/Programs/'+$Group+'/PDFMathTranslate.lnk')))
    $desktop=[Environment]::GetFolderPath('Desktop');Check '桌面快捷方式' (Test-Path -LiteralPath (Join-Path $desktop ($Group+'.lnk')))
    $user=Join-Path $install 'home/用户译文.pdf';New-Item -ItemType Directory -Path (Split-Path -Parent $user)|Out-Null;[IO.File]::WriteAllText($user,'owned test user document; preserve',[Text.UTF8Encoding]::new($false));$userHash=(Get-FileHash -LiteralPath $user).Hash
    $unknown=Join-Path $install '用户说明.txt';[IO.File]::WriteAllText($unknown,'unknown user file',[Text.UTF8Encoding]::new($false))
    # Corrupt/forged prior ownership entries must not turn data roots or
    # traversal paths into program-owned files during upgrade/uninstall.
    $invalid=@('home\用户译文.pdf','.\home\用户译文.pdf','home.\用户译文.pdf','home \用户译文.pdf','HOME~1\用户译文.pdf','..\outside.txt')|ForEach-Object {$_+'|'+$userHash}
    [IO.File]::AppendAllLines((Join-Path $install 'owned-files.tsv'),[string[]]($invalid+@('malformed-entry')),[Text.UTF8Encoding]::new($false))
    Check '初版拥有待淘汰文件' (Test-Path -LiteralPath (Join-Path $install 'test-owned-obsolete.txt'))
    Check '中文相对路径的程序文件已安装' (Test-Path -LiteralPath (Join-Path $install '中文程序文件.txt'))
    $modified=Join-Path $install 'test-owned-modified.txt';[IO.File]::WriteAllText($modified,'user modified owned file',[Text.UTF8Encoding]::new($false))
    # The real installed Release app holds the same mutex checked by Setup and
    # Uninstall. Its home is new and owned; process identity is recorded.
    $profile=Join-Path $repo ('.local/install-profile-'+[guid]::NewGuid().ToString('N').Substring(0,10))
    $env:PDF2ZH_HOME=$profile
    foreach($name in @('PDF2ZH_APP_ROOT','PDF2ZH_RUNTIME_ROOT','PDF2ZH_SOURCE_ROOT')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    $app=Start-Process -FilePath (Join-Path $install 'PDFMathTranslate.exe') -WindowStyle Hidden -PassThru
    try{
        $end=(Get-Date).AddSeconds(50);while(!(Test-Path -LiteralPath (Join-Path $profile 'config/desktop-state.json')) -and !$app.HasExited -and (Get-Date) -lt $end){Start-Sleep -Milliseconds 200}
        Check '安装版 Release 实际启动并建立隔离后端状态' (!$app.HasExited -and (Test-Path -LiteralPath (Join-Path $profile 'config/desktop-state.json'))) @{pid=$app.Id;started=$app.StartTime.ToString('o');path=$app.Path;home=$profile}
        $busy=Run-Setup (Join-Path $install 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $EvidenceRoot 'running-uninstall-negative.log')+'"'))
        Check '运行中卸载被拒且程序保留' ($busy -ne 0 -and (Test-Path -LiteralPath $key) -and (Test-Path -LiteralPath (Join-Path $install 'PDFMathTranslate.exe'))) @{actual_exit=$busy}
    }finally{if(!$app.HasExited -and $app.Path -eq (Join-Path $install 'PDFMathTranslate.exe')){$app.Kill($true);$app.WaitForExit(10000)|Out-Null};$app.Dispose()}
    $runtime=Join-Path $install 'uv-tools';$backup=Join-Path $repo ('.local/installer-runtime-backup-'+[guid]::NewGuid().ToString('N'))
    $outside=Join-Path $repo ('.local/installer-junction-sentinel-'+[guid]::NewGuid().ToString('N'))
    $prefix=[IO.Path]::GetFullPath((Join-Path $repo '.local/'))
    foreach($path in @($runtime,$backup,$outside)){if(![IO.Path]::GetFullPath($path).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw '测试目录移动越界'}}
    New-Item -ItemType Directory -Path $outside|Out-Null;[IO.File]::WriteAllText((Join-Path $outside 'sentinel.txt'),'do not overwrite');$sentinel=(Get-FileHash (Join-Path $outside 'sentinel.txt')).Hash
    Move-Item -LiteralPath $runtime -Destination $backup
    try{
        New-Item -ItemType Junction -Path $runtime -Target $outside|Out-Null
        $rejected=Run-Setup $UpgradeInstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$install+'"'),('/LOG="'+(Join-Path $EvidenceRoot 'junction-upgrade-negative.log')+'"'))
        Check '升级拒绝重解析目录且不写入外部哨兵' ($rejected -ne 0 -and (Get-FileHash (Join-Path $outside 'sentinel.txt')).Hash -eq $sentinel -and @(Get-ChildItem -LiteralPath $outside -Recurse -File).Count -eq 1) @{actual_exit=$rejected}
    }finally{
        $link=Get-Item -LiteralPath $runtime
        if(($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $link.Target -ne $outside){throw '拒绝删除不属于本轮的链接'}
        [IO.Directory]::Delete($runtime)
        Move-Item -LiteralPath $backup -Destination $runtime
    }
    $versionBefore=(Get-FileHash -LiteralPath (Join-Path $install 'version.json')).Hash
    $held=[IO.File]::Open((Join-Path $install 'version.json'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $locked=Run-Setup $UpgradeInstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/RESTARTEXITCODE=3010',('/DIR="'+$install+'"'),('/LOG="'+(Join-Path $EvidenceRoot 'locked-file-negative.log')+'"'))
        Check '锁定文件拒绝覆盖并保留用户文件' ($locked -ne 0 -and (Get-FileHash -LiteralPath (Join-Path $install 'version.json')).Hash -eq $versionBefore -and (Get-FileHash -LiteralPath $user).Hash -eq $userHash) @{actual_exit=$locked;note='normal upgrade follows after unlock'}
    }finally{$held.Dispose()}
    $code=Run-Setup $UpgradeInstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$install+'"'),('/LOG="'+(Join-Path $EvidenceRoot 'upgrade.log')+'"'))
    Check '升级实际退出0' ($code -eq 0)
    Check '升级版本注册信息' ((Get-ItemProperty -LiteralPath $key).DisplayVersion -eq '2.9.1')
    Check '只清理哈希匹配的旧拥有文件' (!(Test-Path -LiteralPath (Join-Path $install 'test-owned-obsolete.txt')) -and (Test-Path -LiteralPath $modified))
    Check '升级保留用户文件' ((Get-FileHash -LiteralPath $user).Hash -eq $userHash -and (Test-Path -LiteralPath $unknown))
    $code=Run-Setup (Join-Path $install 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $EvidenceRoot 'uninstall.log')+'"'))
    Check '卸载实际退出0' ($code -eq 0)
    Check '卸载注册项已清理' (!(Test-Path -LiteralPath $key))
    Check '卸载保留用户文件与已修改文件' ((Get-FileHash -LiteralPath $user).Hash -eq $userHash -and (Test-Path -LiteralPath $unknown) -and (Test-Path -LiteralPath $modified))
    Check '卸载已删除未修改的主程序' (!(Test-Path -LiteralPath (Join-Path $install 'PDFMathTranslate.exe')))
    Check '卸载按UTF8清单删除中文程序文件' (!(Test-Path -LiteralPath (Join-Path $install '中文程序文件.txt')))
    Check '快捷方式已清理' (!(Test-Path -LiteralPath (Join-Path $desktop ($Group+'.lnk'))) -and !(Test-Path -LiteralPath (Join-Path $env:APPDATA ('Microsoft/Windows/Start Menu/Programs/'+$Group+'/PDFMathTranslate.lnk'))))
    $success=$true
}finally{
    @{passed=$success;checks=$rows;app_id=$AppId;group=$Group;install_root=$install;first_installer=$FirstInstaller;upgrade_installer=$UpgradeInstaller;scope='real silent EXE install/upgrade/uninstall and standard registry discovery; Geek GUI and installer mouse input not tested';retention='unknown/modified files retained, empty directories only; test sentinels deliberately retained'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $EvidenceRoot 'result.json') -Encoding utf8
}
if(!$success){exit 1}
