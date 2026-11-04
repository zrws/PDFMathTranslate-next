#requires -Version 7.0
param(
    [string]$BuildDirectory='D:\student\翻译\PDFMathTranslate-next\dist\native-9b66790bc7ea',
    [string]$Output='D:\student\翻译\PDFMathTranslate-next\docs\verification\native-desktop\ardot-independent-package-ee125c188592\nuget-content-review.json'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Refuse observation reuse'}
$repo='D:\student\翻译\PDFMathTranslate-next'
$sdk='D:\student\翻译\toolchains\dotnet10\sdk\10.0.403'
foreach($name in @('NuGet.Common','NuGet.Versioning','NuGet.Packaging')){[Reflection.Assembly]::LoadFrom((Join-Path $sdk ($name+'.dll')))|Out-Null}
$report=Get-Content -LiteralPath (Join-Path $BuildDirectory 'build-report.json') -Raw -Encoding UTF8|ConvertFrom-Json
$deps=Get-Content -LiteralPath (Join-Path $report.payload 'PDFMathTranslate.deps.json') -Raw -Encoding UTF8|ConvertFrom-Json
$locks=Get-Content -LiteralPath (Join-Path $repo 'desktop/PDFMathTranslate.Desktop/packages.lock.json') -Raw -Encoding UTF8|ConvertFrom-Json
$lock=($locks.dependencies.PSObject.Properties|Where-Object Name -NotMatch '/').Value
$target=$deps.targets.PSObject.Properties[$deps.runtimeTarget.name].Value
$rows=foreach($property in $deps.libraries.PSObject.Properties){
    if($property.Value.type -ne 'package'){continue}
    $name,$version=$property.Name -split '/',2
    $packageRoot=Join-Path $repo ('.local/nuget-packages/'+$property.Value.path)
    $nupkg=Join-Path $packageRoot ($name.ToLowerInvariant()+'.'+$version+'.nupkg')
    $reader=[NuGet.Packaging.PackageArchiveReader]::new($nupkg)
    try{
        $contentHash=$reader.GetContentHash([Threading.CancellationToken]::None,$null)
        $expected=$lock.PSObject.Properties[$name].Value.contentHash
        $files=foreach($asset in $target.PSObject.Properties[$property.Name].Value.runtime.PSObject.Properties.Name){
            $stream=$reader.GetStream($asset)
            try{$archiveSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
            $payloadFile=Join-Path $report.payload ([IO.Path]::GetFileName($asset))
            $payloadSha=(Get-FileHash -LiteralPath $payloadFile).Hash
            @{asset=$asset;archive_entry_sha256=$archiveSha;payload_sha256=$payloadSha;matches_archive_bytes=($archiveSha -eq $payloadSha)}
        }
        @{package=$property.Name;nupkg=$nupkg;content_hash=$contentHash;lock_content_hash=$expected;content_hash_matches_lock=($contentHash -eq $expected);runtime_files=@($files)}
    }finally{$reader.Dispose()}
}
$result=@{
    scope='Independent NuGet content semantics and actual archive runtime entry comparison; no installer/application execution'
    correction='Raw SHA512 of a signed ZIP is not the packages.lock contentHash. The original raw-archive comparison is retained and invalid as a package-mismatch verdict.'
    api='NuGet.Packaging.PackageArchiveReader.GetContentHash(CancellationToken.None, null)'
    sdk='10.0.403'
    nuget_packaging_version=[NuGet.Packaging.PackageArchiveReader].Assembly.GetName().Version.ToString()
    nuget_packaging_sha256=(Get-FileHash -LiteralPath (Join-Path $sdk 'NuGet.Packaging.dll')).Hash
    driver_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    checked_at=(Get-Date).ToString('o')
    packages=@($rows)
    passed=(@($rows|Where-Object{!$_.content_hash_matches_lock -or @($_.runtime_files|Where-Object{!$_.matches_archive_bytes}).Count}).Count -eq 0)
}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output -Encoding utf8
@{passed=$result.passed;package_count=$rows.Count;output=$Output}|ConvertTo-Json
