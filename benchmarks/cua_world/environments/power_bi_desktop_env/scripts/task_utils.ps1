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

function Test-PowerBIRendered {
    # True once Power BI Desktop has a real window or a non-trivial working set.
    # A hung cold-boot launch has no main window; a rendered PBI has one.
    $procs = Get-Process PBIDesktop -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }
    foreach ($p in @($procs)) {
        if ($p.MainWindowHandle -ne 0 -or $p.WorkingSet64 -gt 50MB) { return $true }
    }
    return $false
}

function Launch-PowerBIInteractive {
    <#
    .SYNOPSIS
        Launches Power BI Desktop in the interactive desktop session via schtasks /IT
        (Session 1). Retries until PBI actually renders, to survive cold-boot launch hangs.
    .PARAMETER PowerBIExe
        Full path to PBIDesktop.exe.
    .PARAMETER WaitSeconds
        Seconds to poll per attempt before declaring failure (default 30).
    .PARAMETER MaxAttempts
        Number of kill-and-relaunch retries (default 4).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PowerBIExe,
        [int]$WaitSeconds = 30,
        [int]$MaxAttempts = 4
    )

    if (-not (Test-Path $PowerBIExe)) {
        throw "Power BI Desktop executable not found at: $PowerBIExe"
    }

    $launchScript = "C:\Windows\Temp\launch_powerbi.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$PowerBIExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchPowerBI_GA"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Cold-boot interactive sessions can hang the first GUI launch. Launch, verify
        # PBI actually rendered a window, and retry (kill + relaunch) until it does.
        # Replaces the savevm checkpoint that pre-baked a warmed, rendered PBI.
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            schtasks /Delete /TN $taskName /F 2>$null
            $waited = 0
            while ($waited -lt $WaitSeconds) {
                Start-Sleep -Seconds 3
                $waited += 3
                if (Test-PowerBIRendered) { break }
            }
            if (Test-PowerBIRendered) {
                Write-Host "Power BI Desktop rendered on attempt $attempt."
                return
            }
            Write-Host "Power BI Desktop did not render on attempt $attempt (cold-boot hang); retrying..."
        }
        Write-Host "WARNING: Power BI Desktop failed to render after $MaxAttempts attempts."
    } finally {
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}
