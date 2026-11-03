Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
# Local path discovery. No network, global environment changes or cache lookup.
function Resolve-P0EvidenceRoot([string]$RepoRoot, [string]$EvidenceRoot) {
    if ($EvidenceRoot) { return [IO.Path]::GetFullPath($EvidenceRoot) }
    return Join-Path $RepoRoot ('docs\verification\native-desktop\local-' +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
}
function Resolve-P0Python([string]$InstallRoot, [string]$PythonExe) {
    if ($PythonExe) {
        if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw 'PythonExe missing' }
        return [IO.Path]::GetFullPath($PythonExe)
    }
    $base = if ($InstallRoot) { Join-Path $InstallRoot 'uv-python' } else { '' }
    if ($base -and (Test-Path -LiteralPath $base)) {
        $found = @(Get-ChildItem -LiteralPath $base -Recurse -Filter python.exe -File)
        if ($found.Count -eq 1) { return $found[0].FullName }
        if ($found.Count -gt 1) { throw 'Ambiguous Python runtime; specify -PythonExe' }
    }
    # Pure local stubs may use the existing standard-library interpreter.
    # Product entry scripts independently require their locked package tree.
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike '*WindowsApps*') { return $cmd.Source }
    throw 'Python runtime unavailable; specify -PythonExe (no automatic download)'
}
function ConvertTo-P0Argument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including embedded quotes/trailing slash.
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}
function Start-P0PowerShell {
    param([string]$ArgumentList, [string]$RedirectStandardOutput,
          [string]$RedirectStandardError, [switch]$Wait,
          [switch]$PassThru, [switch]$NoNewWindow)
    # PS7's module path must not be inherited by Windows PowerShell 5.1.
    # Scope this change to process creation and restore it before any wait.
    $previous = [Environment]::GetEnvironmentVariable('PSModulePath')
    $previousBytecode = [Environment]::GetEnvironmentVariable('PYTHONDONTWRITEBYTECODE')
    $options = @{ FilePath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe');
        ArgumentList = $ArgumentList; PassThru = $true; NoNewWindow = $true }
    if ($RedirectStandardOutput) { $options.RedirectStandardOutput = $RedirectStandardOutput }
    if ($RedirectStandardError) { $options.RedirectStandardError = $RedirectStandardError }
    try {
        $env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
        $env:PYTHONDONTWRITEBYTECODE = '1'
        $child = Start-Process @options
        # .NET Framework Process must retain a handle BEFORE a short child exits;
        # otherwise WinPS 5.1 can return null ExitCode after WaitForExit.
        $null = $child.Handle
    } finally {
        [Environment]::SetEnvironmentVariable('PSModulePath', $previous, 'Process')
        [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', $previousBytecode, 'Process')
    }
    if ($Wait) { $child.WaitForExit(); $child.Refresh() }
    return $child
}
function Invoke-P0PythonFile {
    param([string]$PythonExe, [string]$ScriptFile, [string]$IsolatedHome,
          [string]$PythonPath, [string]$GuardDir, [string]$LogPrefix,
          [string[]]$ScriptArgs = @(), [string]$GuardLog = '', [int]$TimeoutSeconds = 60)
    $iso = [IO.Path]::GetFullPath($IsolatedHome)
    foreach ($dir in @($iso, (Join-Path $iso 'work'), (Join-Path $iso 'tmp'), (Join-Path $iso '.config\pdf2zh'))) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $config = Join-Path $iso '.config\pdf2zh\config.v3.toml'
    if (-not (Test-Path $config)) { '' | Set-Content $config -Encoding ASCII }
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $PythonExe
    $psi.Arguments = ConvertTo-P0Argument (Join-Path $GuardDir 'entry_wrapper.py')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = Join-Path $iso 'work'
    $remove = @($psi.EnvironmentVariables.Keys | Where-Object { $_ -like '*_PROXY' -or $_ -like 'PDF2ZH_*' -or $_ -like 'BABELDOC_*' })
    foreach ($key in $remove) { $psi.EnvironmentVariables.Remove($key) | Out-Null }
    if (-not $GuardLog) { $GuardLog = $LogPrefix + '.guard.log' }
    $values = @{ HOME=$iso; USERPROFILE=$iso; APPDATA=(Join-Path $iso 'AppData\Roaming'); LOCALAPPDATA=(Join-Path $iso 'AppData\Local'); TEMP=(Join-Path $iso 'tmp'); TMP=(Join-Path $iso 'tmp'); XDG_CACHE_HOME=(Join-Path $iso '.cache'); PDF2ZH_HOME=$iso; PDF2ZH_CONFIG_FILE=$config; PYTHONUTF8='1'; PYTHONNOUSERSITE='1'; PYTHONPATH=($GuardDir + ';' + $PythonPath); PDF2ZH_GUARD_LOG=$GuardLog; PDF2ZH_GUARD_DIR=$GuardDir; PDF2ZH_GUARD_SHA256=(Get-FileHash (Join-Path $GuardDir 'sitecustomize.py') -Algorithm SHA256).Hash; PDF2ZH_TARGET_SCRIPT=$ScriptFile; PDF2ZH_TARGET_ARGS_JSON=(ConvertTo-Json -InputObject @($ScriptArgs) -Compress); PDF2ZH_RUN_ID=[guid]::NewGuid().ToString('N'); PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; GRADIO_ANALYTICS_ENABLED='False' }
    foreach ($key in $values.Keys) { $psi.EnvironmentVariables[$key] = $values[$key] }
    $child = [Diagnostics.Process]::Start($psi)
    $out = $child.StandardOutput.ReadToEndAsync(); $err = $child.StandardError.ReadToEndAsync()
    if (-not $child.WaitForExit($TimeoutSeconds * 1000)) { $child.Kill(); throw 'isolated Python child timed out' }
    $out.Result | Set-Content ($LogPrefix + '.stdout.txt') -Encoding UTF8
    $err.Result | Set-Content ($LogPrefix + '.stderr.txt') -Encoding UTF8
    @{ pid=$child.Id; actual_exit=$child.ExitCode; isolated_home=$iso; script=$ScriptFile; python=$PythonExe } | ConvertTo-Json | Set-Content ($LogPrefix + '.observed.json') -Encoding UTF8
    return $child.ExitCode
}
