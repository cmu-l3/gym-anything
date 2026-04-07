# task_utils.ps1 — Shared utility functions for StudioTax tasks

function Find-StudioTaxExe {
    <#
    .SYNOPSIS
    Locates the StudioTax 2024 executable on the system.
    #>

    # Check cached path first
    $cachedPath = "C:\Users\Docker\studiotax_path.txt"
    if (Test-Path $cachedPath) {
        try {
            $path = (Get-Content $cachedPath -Raw -ErrorAction SilentlyContinue)
            if ($path) {
                $path = $path.Trim()
                if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
                    return $path
                }
            }
        } catch {
            Write-Host "WARNING: Cached path file unreadable, ignoring"
        }
    }

    # Check standard install locations (actual path: BHOK IT Consulting Inc)
    $candidates = @(
        "C:\Program Files\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe",
        "C:\Program Files (x86)\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe",
        "C:\Program Files\BHOK IT Consulting\StudioTax 2024\StudioTax.exe",
        "C:\Program Files (x86)\BHOK IT Consulting\StudioTax 2024\StudioTax.exe",
        "C:\Program Files\StudioTax 2024\StudioTax.exe",
        "C:\Program Files (x86)\StudioTax 2024\StudioTax.exe"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            # Cache the found path
            Set-Content -Path $cachedPath -Value $path -ErrorAction SilentlyContinue
            return $path
        }
    }

    # Recursive search in Program Files
    $searchBases = @("C:\Program Files", "C:\Program Files (x86)", "C:\Users\Docker")
    foreach ($base in $searchBases) {
        $found = Get-ChildItem -Path $base -Recurse -Filter "StudioTax.exe" -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -eq "StudioTax.exe" } | Select-Object -First 1
        if ($found) {
            Set-Content -Path $cachedPath -Value $found.FullName -ErrorAction SilentlyContinue
            return $found.FullName
        }
    }

    # Try any StudioTax executable as fallback
    foreach ($base in $searchBases) {
        $found = Get-ChildItem -Path $base -Recurse -Filter "StudioTax*.exe" -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notmatch "Install|Setup|Uninstall" } |
                 Select-Object -First 1
        if ($found) {
            Set-Content -Path $cachedPath -Value $found.FullName -ErrorAction SilentlyContinue
            return $found.FullName
        }
    }

    return $null
}

function Launch-StudioTaxInteractive {
    <#
    .SYNOPSIS
    Launches StudioTax in the interactive desktop session using schtasks /IT.
    .PARAMETER StudioTaxExe
    Full path to StudioTax executable.
    .PARAMETER WaitSeconds
    Seconds to wait after launching.
    .PARAMETER Arguments
    Optional command-line arguments for StudioTax.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$StudioTaxExe,

        [int]$WaitSeconds = 15,

        [string]$Arguments = ""
    )

    $launchScript = "C:\Windows\Temp\launch_studiotax.cmd"

    if ($Arguments) {
        $cmdContent = "@echo off`r`nstart `"`" `"$StudioTaxExe`" $Arguments"
    } else {
        $cmdContent = "@echo off`r`nstart `"`" `"$StudioTaxExe`""
    }

    Set-Content -Path $launchScript -Value $cmdContent -Encoding ASCII

    $taskName = "LaunchStudioTax_GA"
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName /TR "cmd /c `"$launchScript`"" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    $ErrorActionPreference = "Stop"

    Start-Sleep -Seconds $WaitSeconds

    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName /F 2>$null
    Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"
}

function Get-StudioTaxReturnFiles {
    <#
    .SYNOPSIS
    Finds all .24t StudioTax return files in the Documents directory.
    #>
    param(
        [string]$SearchPath = "C:\Users\Docker\Documents"
    )

    $files = Get-ChildItem -Path $SearchPath -Recurse -Filter "*.24t" -ErrorAction SilentlyContinue
    return $files
}

function Get-TaskStartTimestamp {
    <#
    .SYNOPSIS
    Reads the task start timestamp file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName
    )

    $tsFile = "C:\Users\Docker\task_start_timestamp_$TaskName.txt"
    if (Test-Path $tsFile) {
        return [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
    }
    return 0
}
