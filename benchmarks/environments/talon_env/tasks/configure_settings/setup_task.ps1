Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_configure_settings.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up configure_settings task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Ensure the community settings.talon is present
    $settingsFile = "$Script:CommunityDir\settings.talon"
    if (-not (Test-Path $settingsFile)) {
        Write-Host "settings.talon not found at community dir, copying from data..."
        $dataSource = "C:\workspace\data\community_sample\settings.talon"
        if (Test-Path $dataSource) {
            New-Item -ItemType Directory -Force -Path $Script:CommunityDir | Out-Null
            Copy-Item $dataSource -Destination $settingsFile -Force
        } else {
            throw "settings.talon not found in data either"
        }
    }

    # Reset the file to original state (in case of previous task runs)
    $dataSource = "C:\workspace\data\community_sample\settings.talon"
    if (Test-Path $dataSource) {
        Copy-Item $dataSource -Destination $settingsFile -Force
        Write-Host "Reset settings.talon to original state"
    }

    # Open the settings file in the editor
    Write-Host "Opening settings.talon in editor..."
    Open-FileInteractive -FilePath $settingsFile -WaitSeconds 8

    # Minimize terminal windows
    Minimize-TerminalWindows

    Write-Host "=== configure_settings task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
