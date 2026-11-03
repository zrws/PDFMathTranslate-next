param([Parameter(Mandatory=$true)][string]$PayloadRoot,[Parameter(Mandatory=$true)][string]$IsccExe)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$PayloadRoot=(Resolve-Path -LiteralPath $PayloadRoot).Path
if(!$PayloadRoot.StartsWith((Join-Path $repo '.local/build-native-'),[StringComparison]::OrdinalIgnoreCase)){throw '仅允许本轮构建载荷'}
$id=[guid]::NewGuid().ToString('N').Substring(0,12)
$stage=Join-Path $repo ('.local/install-test-payload-'+$id)
$output=Join-Path $repo ('dist/install-tests-'+$id)
New-Item -ItemType Directory -Path $stage,$output|Out-Null
& robocopy $PayloadRoot $stage /E /MT:4 /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XF owned-files.tsv version.json
if($LASTEXITCODE -lt 0 -or $LASTEXITCODE -ge 8){throw '复制测试安装载荷失败'}
$appId='PDFMathTranslate-Codex-Test-'+$id
function Manifest {
    $rows=Get-ChildItem -LiteralPath $stage -File -Recurse|Where-Object Name -ne 'owned-files.tsv'|Sort-Object FullName|ForEach-Object {$_.FullName.Substring($stage.Length+1)+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}
    [IO.File]::WriteAllLines((Join-Path $stage 'owned-files.tsv'),[string[]]$rows,[Text.UTF8Encoding]::new($true))
}
foreach($name in @('test-owned-obsolete.txt','test-owned-modified.txt','中文程序文件.txt')){[IO.File]::WriteAllText((Join-Path $stage $name),'本轮拥有的安装测试文件',[Text.UTF8Encoding]::new($false))}
@{version='2.9.0';channel='preview'}|ConvertTo-Json|Set-Content (Join-Path $stage 'version.json') -Encoding utf8
Manifest
& $IsccExe '/DAppVersion=2.9.0' "/DAppGuid=$appId" "/DAppGroup=$appId" "/DPayloadRoot=$stage" "/DInstallerOutputDir=$output" (Join-Path $repo 'build/installer.iss') *> (Join-Path $output 'first-compile.log')
if($LASTEXITCODE){throw '首版测试安装器编译失败'}
foreach($name in @('test-owned-obsolete.txt','test-owned-modified.txt')){Remove-Item -LiteralPath (Join-Path $stage $name)}
@{version='2.9.1';channel='preview'}|ConvertTo-Json|Set-Content (Join-Path $stage 'version.json') -Encoding utf8
Manifest
& $IsccExe '/DAppVersion=2.9.1' "/DAppGuid=$appId" "/DAppGroup=$appId" "/DPayloadRoot=$stage" "/DInstallerOutputDir=$output" (Join-Path $repo 'build/installer.iss') *> (Join-Path $output 'upgrade-compile.log')
if($LASTEXITCODE){throw '升级测试安装器编译失败'}
$first=Join-Path $output 'PDFMathTranslate-Setup-2.9.0.exe';$upgrade=Join-Path $output 'PDFMathTranslate-Setup-2.9.1.exe'
@{app_id=$appId;group=$appId;source_payload=$PayloadRoot;test_payload=$stage;first=$first;first_sha256=(Get-FileHash $first).Hash;upgrade=$upgrade;upgrade_sha256=(Get-FileHash $upgrade).Hash;source_commit=(& git -C $repo rev-parse HEAD)}|ConvertTo-Json|Set-Content (Join-Path $output 'installers.json') -Encoding utf8
$output|Set-Content (Join-Path $repo '.git/install-test-output.txt')
Write-Output $output
