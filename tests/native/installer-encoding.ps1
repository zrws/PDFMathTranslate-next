param([Parameter(Mandatory=$true)][string]$IsccExe,[Parameter(Mandatory=$true)][string]$EvidenceRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(Test-Path -LiteralPath $EvidenceRoot){throw '证据目录必须全新'}
New-Item -ItemType Directory -Path $EvidenceRoot|Out-Null
$rows=@()
foreach($bom in @($false,$true)){
    $id='PDFMathTranslate-Codex-Test-'+[guid]::NewGuid().ToString('N')
    $stage=Join-Path $repo ('.local/manifest-fixture-'+$id)
    $installed=Join-Path $repo ('.local/中文清单-'+$id)
    $output=Join-Path $EvidenceRoot ([string]$bom)
    New-Item -ItemType Directory -Path $stage,$output|Out-Null
    $files=@('中文程序文件.txt','ascii.txt')
    foreach($file in $files){[IO.File]::WriteAllText((Join-Path $stage $file),'UTF8 owned fixture',[Text.UTF8Encoding]::new($false))}
    $manifest=$files|ForEach-Object {$_+'|'+(Get-FileHash -LiteralPath (Join-Path $stage $_)).Hash}
    [IO.File]::WriteAllLines((Join-Path $stage 'owned-files.tsv'),[string[]]$manifest,[Text.UTF8Encoding]::new($bom))
    & $IsccExe '/DAppVersion=0.0.0' "/DAppGuid=$id" "/DAppGroup=$id" "/DPayloadRoot=$stage" "/DInstallerOutputDir=$output" (Join-Path $repo 'build/installer.iss') *> (Join-Path $output 'compile.log')
    if($LASTEXITCODE){throw 'fixture compile failed'}
    $installer=Join-Path $output 'PDFMathTranslate-Setup-0.0.0.exe'
    $p=Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$installed+'"'),'/TASKS=""',('/LOG="'+(Join-Path $output 'install.log')+'"')) -WindowStyle Hidden -PassThru -Wait
    $installExit=$p.ExitCode
    if($installExit -ne 0){throw 'fixture install failed'}
    $p=Start-Process -FilePath (Join-Path $installed 'unins000.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $output 'uninstall.log')+'"')) -WindowStyle Hidden -PassThru -Wait
    $row=@{bom=$bom;install_exit=$installExit;uninstall_exit=$p.ExitCode;installed=$installed;remaining=@($files|Where-Object {Test-Path -LiteralPath (Join-Path $installed $_)});registry_removed=!(Test-Path -LiteralPath ('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$id+'_is1'))}
    $rows+=$row
    $rows|ConvertTo-Json -Depth 5|Set-Content (Join-Path $EvidenceRoot 'result.json') -Encoding utf8
    if($bom -and ($row.uninstall_exit -ne 0 -or $row.remaining.Count -ne 0 -or !$row.registry_removed)){throw 'BOM ownership cleanup failed'}
}
