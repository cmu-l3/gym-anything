# task_utils.ps1 - Shared helper functions for Azure DevOps Server task setup scripts.

function Get-AzureDevOpsUrl {
    <#
    .SYNOPSIS
        Gets the Azure DevOps base URL from the saved config file.
    .OUTPUTS
        String URL like "http://localhost/DefaultCollection"
    #>
    $urlFile = "C:\Users\Docker\azure_devops_url.txt"
    if (Test-Path $urlFile) {
        return (Get-Content $urlFile -Raw).Trim()
    }

    # Fallback: probe common URLs
    $candidates = @(
        "http://localhost/DefaultCollection",
        "http://localhost:8080/tfs/DefaultCollection"
    )
    foreach ($url in $candidates) {
        try {
            $r = Invoke-WebRequest -Uri "$url/_apis/projects?api-version=7.1" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                $url | Out-File -FilePath $urlFile -Force
                return $url
            }
        } catch {}
    }

    throw "Cannot determine Azure DevOps Server URL. Is the server running?"
}

function Wait-AzureDevOpsReady {
    <#
    .SYNOPSIS
        Waits for Azure DevOps web interface to respond.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait (default 60).
    #>
    param([int]$TimeoutSeconds = 60)

    $baseUrl = Get-AzureDevOpsUrl
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $r = Invoke-WebRequest -Uri "$baseUrl/_apis/projects?api-version=7.1" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                return $baseUrl
            }
        } catch {}
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    throw "Azure DevOps not ready after ${TimeoutSeconds}s"
}

function Find-EdgeExe {
    <#
    .SYNOPSIS
        Finds the Microsoft Edge executable on the system.
    .OUTPUTS
        String path to msedge.exe
    #>
    $searchPaths = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    )

    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    throw "Microsoft Edge executable not found."
}

function Launch-EdgeInteractive {
    <#
    .SYNOPSIS
        Launches Microsoft Edge in the interactive desktop session via schtasks.
    .PARAMETER Url
        URL to open in Edge.
    .PARAMETER WaitSeconds
        Seconds to wait for Edge to load (default 10).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [int]$WaitSeconds = 10
    )

    $edgeExe = Find-EdgeExe
    $launchScript = "C:\Windows\Temp\launch_edge.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$edgeExe`" --no-first-run --disable-sync --no-default-browser-check `"$Url`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchEdge_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $futureTime = (Get-Date).AddMinutes(2).ToString("HH:mm")
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $futureTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "Edge launched to: $Url (waited ${WaitSeconds}s)"
}

function Suppress-OneDrive {
    <#
    .SYNOPSIS
        Kills OneDrive processes and suppresses all toast notifications.
    #>
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Remove from startup
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
    # Suppress OneDrive notifications
    $notifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop"
    if (-not (Test-Path $notifPath)) { New-Item -Path $notifPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $notifPath -Name "Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    # Disable toast notifications globally
    $wpnPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $wpnPath)) { New-Item -Path $wpnPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $wpnPath -Name "ToastEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    # Disable Windows Backup reminder toast
    $backupNotifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.BackupReminder"
    if (-not (Test-Path $backupNotifPath)) { New-Item -Path $backupNotifPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $backupNotifPath -Name "Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    # Disable notification center
    $explorerPolicyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $explorerPolicyPath)) { New-Item -Path $explorerPolicyPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $explorerPolicyPath -Name "DisableNotificationCenter" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    # Uninstall if still present
    $odSetup = "C:\Windows\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $odSetup)) { $odSetup = "C:\Windows\System32\OneDriveSetup.exe" }
    if (Test-Path $odSetup) {
        Start-Process $odSetup -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
    }
    Write-Host "OneDrive suppressed."
}

function Dismiss-Notifications {
    <#
    .SYNOPSIS
        Dismisses any visible toast notifications by clicking their close buttons via PyAutoGUI.
        Falls back to restarting explorer if PyAutoGUI is unavailable.
    #>
    try {
        # Try to connect to PyAutoGUI server to dismiss notifications
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect("localhost", 5555)
        $stream = $tcpClient.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)

        # Click common notification close areas (bottom-right toast dismiss)
        # Windows 11 toast notifications appear at bottom-right
        $clicks = @(
            @{ x = 1237; y = 392 },   # OneDrive popup X button
            @{ x = 1167; y = 626 },   # "No thanks" button
            @{ x = 1260; y = 10 }     # System tray area dismiss
        )

        foreach ($pos in $clicks) {
            $cmd = '{"action":"click","x":' + $pos.x + ',"y":' + $pos.y + ',"button":"left","clicks":1}' + "`n"
            $writer.Write($cmd)
            $writer.Flush()
            Start-Sleep -Milliseconds 200
            $null = $reader.ReadLine()
        }

        $writer.Close()
        $reader.Close()
        $tcpClient.Close()
        Write-Host "Notifications dismissed via PyAutoGUI."
    } catch {
        # Fallback: restart explorer to clear notification area
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process "explorer.exe"
        Start-Sleep -Seconds 3
        Write-Host "Notifications cleared via explorer restart."
    }
}

function Clean-DesktopForTask {
    <#
    .SYNOPSIS
        Prepares the desktop for a clean task start: kills Edge, suppresses OneDrive, dismisses notifications.
    #>
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Suppress-OneDrive
    Dismiss-Notifications
    Start-Sleep -Seconds 3
}

function Invoke-AzDevOpsApi {
    <#
    .SYNOPSIS
        Calls Azure DevOps REST API with NTLM credentials.
    .PARAMETER Path
        API path relative to base URL (e.g., "/TailwindTraders/_apis/wit/workitems").
    .PARAMETER Method
        HTTP method (default GET).
    .PARAMETER Body
        Request body string.
    .PARAMETER ContentType
        Content type (default application/json).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$Method = "GET",
        [string]$Body = $null,
        [string]$ContentType = "application/json"
    )

    $baseUrl = Get-AzureDevOpsUrl
    $fullUrl = "$baseUrl$Path"

    $params = @{
        Uri = $fullUrl
        Method = $Method
        UseDefaultCredentials = $true
        ContentType = $ContentType
    }

    if ($Body) {
        $params["Body"] = $Body
    }

    return Invoke-RestMethod @params
}
