# Setup script for create_console_project task.
# Launches VS 2022 to the Start Window (no solution open).

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_create_console_project.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up create_console_project task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Kill any existing VS instances
    Kill-AllVS2022

    # Remove any previous HelloWorld project so the task starts fresh
    $helloWorldDir = "C:\Users\Docker\source\repos\HelloWorld"
    if (Test-Path $helloWorldDir) {
        Remove-Item $helloWorldDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed existing HelloWorld project."
    }

    # Launch VS without a solution -- this opens the Start Window
    $devenvExe = Find-VS2022Exe
    Write-Host "VS executable: $devenvExe"
    Write-Host "Launching VS to Start Window (no solution)..."
    Launch-VS2022Interactive -DevenvExe $devenvExe -WaitSeconds 20

    # Dismiss any startup dialogs
    Write-Host "Dismissing dialogs..."
    try {
        Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 3 -BetweenRetriesSeconds 2
        Write-Host "Dialog dismissal complete."
    } catch {
        Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
    }

    $vsProc = Get-Process devenv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vsProc) {
        Write-Host "VS is running (PID: $($vsProc.Id))"
    } else {
        Write-Host "WARNING: VS process not found after launch."
    }

    Write-Host "=== create_console_project task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
