# task_utils.ps1 - Shared helper functions for Tier2 Submit task setup scripts.

function Find-Tier2SubmitExe {
    <#
    .SYNOPSIS
        Finds the Tier2 Submit executable on the system.
    .OUTPUTS
        String path to Tier2 Submit executable
    #>
    $searchPaths = @(
        # Actual installed path (Tier2 Submit 2025 Rev 1 - Inno Setup)
        "C:\Program Files (x86)\Tier2 Submit 2025 Rev 1\Tier2 Submit.exe",
        "C:\Program Files\Tier2 Submit 2025 Rev 1\Tier2 Submit.exe",
        # Other possible versioned paths
        "C:\Program Files (x86)\Tier2 Submit 2025\Tier2 Submit.exe",
        "C:\Program Files\Tier2 Submit 2025\Tier2 Submit.exe",
        # Generic paths
        "C:\Program Files (x86)\Tier2 Submit\Tier2 Submit.exe",
        "C:\Program Files\Tier2 Submit\Tier2 Submit.exe",
        "C:\Program Files (x86)\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files\Tier2Submit\Tier2Submit.exe"
    )

    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Broader search in Program Files - prefer main GUI exe over server/helper exes
    $searchDirs = @("C:\Program Files (x86)", "C:\Program Files")
    foreach ($dir in $searchDirs) {
        $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue -Depth 3 |
            Where-Object { $_.Name -match "(?i)tier.?2.?submit" -and $_.Name -notmatch "(?i)unins|setup|server|install" } |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw "Tier2 Submit executable not found. Is it installed?"
}

function Launch-Tier2SubmitInteractive {
    <#
    .SYNOPSIS
        Launches Tier2 Submit in the interactive desktop session via schtasks.
    .PARAMETER Tier2SubmitExe
        Full path to Tier2 Submit executable.
    .PARAMETER Arguments
        Optional command-line arguments.
    .PARAMETER WaitSeconds
        Seconds to wait for Tier2 Submit to fully load (default 20).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Tier2SubmitExe,
        [string]$Arguments = "",
        [int]$WaitSeconds = 20
    )

    $launchScript = "C:\Windows\Temp\launch_tier2submit.cmd"
    if ($Arguments) {
        $batchContent = "@echo off`r`nstart `"`" `"$Tier2SubmitExe`" $Arguments"
    } else {
        $batchContent = "@echo off`r`nstart `"`" `"$Tier2SubmitExe`""
    }
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchTier2Submit_GA"
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

    Write-Host "Tier2 Submit launched (waited ${WaitSeconds}s)."
}

function Stop-Tier2Submit {
    <#
    .SYNOPSIS
        Stops all Tier2 Submit related processes.
    #>
    Get-Process | Where-Object {
        $_.ProcessName -match "(?i)tier2|t2s|t2submit|filemaker|fmapp"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "Tier2 Submit processes stopped."
}

function Get-TaskStartTimestamp {
    <#
    .SYNOPSIS
        Gets the current epoch timestamp for task start recording.
    .OUTPUTS
        Integer epoch seconds
    #>
    return [int][double]::Parse((Get-Date -UFormat %s))
}

function Record-TaskStart {
    <#
    .SYNOPSIS
        Records the task start timestamp to a file for anti-gaming verification.
    .PARAMETER TaskName
        Name of the task.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName
    )

    $epoch = Get-TaskStartTimestamp
    $timestampFile = "C:\Users\Docker\task_start_timestamp_${TaskName}.txt"
    Set-Content -Path $timestampFile -Value "$epoch"
    Write-Host "Start timestamp recorded: $epoch"
    return $epoch
}

function Write-ResultJson {
    <#
    .SYNOPSIS
        Writes a result JSON file for the verifier to consume.
    .PARAMETER TaskName
        Name of the task.
    .PARAMETER Data
        Hashtable of result data.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName,
        [Parameter(Mandatory=$true)]
        [hashtable]$Data
    )

    $resultPath = "C:\Users\Docker\Desktop\${TaskName}_result.json"
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $resultPath -Encoding UTF8
    Write-Host "Result JSON written to: $resultPath"
}
