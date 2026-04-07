Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Post-start hook for eQUEST environment.
# Configures eQUEST registration, copies data files, suppresses notifications.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up eQUEST environment ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils; Write-Host "Loaded task_utils.ps1" }

    # Copy real building data files from workspace to Desktop
    $projectsDir = "C:\Users\Docker\Desktop\eQUEST_Projects"
    New-Item -ItemType Directory -Force -Path $projectsDir | Out-Null
    if (Test-Path "C:\workspace\data") {
        Copy-Item "C:\workspace\data\*" -Destination $projectsDir -Force -ErrorAction SilentlyContinue
        Write-Host "Building model files copied to: $projectsDir"
    }

    # Locate eQUEST executable
    $eqExe = $null
    try { $eqExe = Find-EqExe } catch { }
    if (-not $eqExe) {
        @("C:\Program Files (x86)\eQUEST 3-65-7175\eQUEST.exe",
          "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe") | ForEach-Object {
            if ((Test-Path $_) -and -not $eqExe) { $eqExe = $_ }
        }
    }
    if ($eqExe) { Write-Host "eQUEST found at: $eqExe" }
    else { Write-Host "WARNING: eQUEST executable not found." }

    # Configure eQUEST INI with registration code and data paths
    if ($eqExe) {
        $eqInstDir = Split-Path $eqExe -Parent
        $installIni = "$eqInstDir\eQUEST.ini"
        $dataPath = "C:\Users\Docker\Documents\eQUEST 3-65-7175 Data\"
        $projPath = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\"
        New-Item -ItemType Directory -Force -Path $projPath -ErrorAction SilentlyContinue | Out-Null

        $iniContent = "[paths]`r`nDataPath=`"$dataPath`"`r`nProjPath=`"$projPath`"`r`n`r`n[Registration]`r`nCode=9349417631702397005-001`r`nStatus=1000`r`nSpecial=581413115`r`n"
        [System.IO.File]::WriteAllText($installIni, $iniContent, [System.Text.Encoding]::ASCII)
        Write-Host "eQUEST.ini configured (with registration code)"

        # Also ensure data dir INI has correct registration
        Restore-EqRegistration
    }

    # Disable Windows notifications that interfere with GUI automation
    $notifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    if (-not (Test-Path $notifPath)) { New-Item -Path $notifPath -Force | Out-Null }
    Set-ItemProperty -Path $notifPath -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) { New-Item -Path $backupPath -Force | Out-Null }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Clean up desktop in Session 1 (minimize terminals, close Start menu)
    $cleanupScript = "C:\Windows\Temp\cleanup_desktop.ps1"
    @'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
(New-Object -ComObject Shell.Application).MinimizeAll()
'@ | Set-Content $cleanupScript -Encoding UTF8
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "CleanupDesktop_GA" /TR "powershell -ExecutionPolicy Bypass -File $cleanupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "CleanupDesktop_GA" 2>$null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN "CleanupDesktop_GA" /F 2>$null
    Remove-Item $cleanupScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP2

    Write-Host "Available building models:"
    Get-ChildItem $projectsDir -Filter "*.inp" | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "=== eQUEST environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
