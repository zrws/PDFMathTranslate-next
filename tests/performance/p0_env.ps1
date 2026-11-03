# Shared environment save/restore helper (ASCII only, PS 5.1 safe)
# T2/S3: case-insensitive dedup, existed+value structure, try/finally guarantee.
# Every managed key is saved as @{ existed = $true/$false; value = <string or $null> }
# including keys that did NOT exist before; Restore-ChildEnv then restores the
# original value or REMOVES keys that were newly created during the run.
# Usage:
#   . p0_env.ps1
#   $saved = Save-ChildEnv @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','PDF2ZH_GUARD_LOG')
#   try { ... } finally { Restore-ChildEnv $saved }

function Save-ChildEnv {
    param([string[]]$Names)
    $saved = @{}
    foreach ($n in $Names) {
        # PS hashtables are case-insensitive by default: HTTP_PROXY and
        # http_proxy are the same key. Save each unique name ONCE by checking
        # if we've already seen a case-insensitive match.
        $alreadySaved = $false
        foreach ($k in $saved.Keys) {
            if ($k -ieq $n) { $alreadySaved = $true; break }
        }
        if (-not $alreadySaved) {
            $val = [Environment]::GetEnvironmentVariable($n)
            # S3: record existed=true/false + value for EVERY managed key,
            # including keys that did not exist (so restore can delete them).
            $saved[$n] = @{ existed = ($null -ne $val); value = $val }
        }
    }
    return $saved
}

function Clear-ChildEnv {
    param([string[]]$Names)
    # Clear all case variants of each name
    foreach ($n in $Names) {
        Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue
        # PS env provider is case-insensitive on Windows, so clearing
        # the canonical name clears all variants
    }
}

function Restore-ChildEnv {
    param($Saved)
    foreach ($k in $Saved.Keys) {
        $entry = $Saved[$k]
        if ($entry -is [hashtable] -or $entry.existed -ne $null) {
            # S3 existed/value structure
            if ($entry.existed) {
                if ($null -ne $entry.value) {
                    Set-Item ("Env:" + $k) $entry.value
                } else {
                    Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue
                }
            } else {
                # key did not exist before this run: delete anything created now
                Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue
            }
        } else {
            # legacy flat string value (backwards compatibility)
            Set-Item ("Env:" + $k) $entry
        }
    }
}

function Set-ChildEnvBlock {
    # Convenience: save, clear, and return the saved state
    param([string[]]$Names)
    $saved = Save-ChildEnv $Names
    Clear-ChildEnv $Names
    return $saved
}
