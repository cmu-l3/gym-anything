# task_utils.ps1 - Shared helper functions for Power BI Desktop task setup scripts.

function Find-PowerBIExe {
    <#
    .SYNOPSIS
        Finds the Power BI Desktop executable on the system.
    .OUTPUTS
        String path to PBIDesktop.exe
    #>
    $searchPaths = @(
        "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
        "C:\Program Files (x86)\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    )

    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Broader search
    $found = Get-ChildItem "C:\Program Files" -Recurse -Filter "PBIDesktop.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }

    throw "Power BI Desktop executable not found. Is it installed?"
}

function Launch-PowerBIInteractive {
    <#
    .SYNOPSIS
        Launches Power BI Desktop in the interactive desktop session via schtasks.
    .PARAMETER PowerBIExe
        Full path to PBIDesktop.exe.
    .PARAMETER WaitSeconds
        Seconds to wait for Power BI to fully load (default 15).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PowerBIExe,
        [int]$WaitSeconds = 15
    )

    $launchScript = "C:\Windows\Temp\launch_powerbi.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$PowerBIExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchPowerBI_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "Power BI Desktop launched (waited ${WaitSeconds}s)."
}
