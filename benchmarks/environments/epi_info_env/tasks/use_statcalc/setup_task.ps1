Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_use_statcalc.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up use_statcalc task ==="

    # Source shared utilities
    . C:\workspace\scripts\task_utils.ps1

    # 1. Start Edge killer
    $edgeKiller = Start-EdgeKillerTask

    # 2. Kill existing Epi Info processes
    Close-Browsers
    Stop-EpiInfo

    # 3. Launch StatCalc module directly
    Write-Host "Launching Epi Info 7 StatCalc (StatCalc.exe)..."
    Launch-EpiInfoModuleInteractive -ModuleExe "StatCalc.exe" -WaitSeconds 12

    # 4. Dismiss any startup dialogs
    Dismiss-EpiInfoDialogs -Retries 3 -WaitSeconds 2

    # 5. Bring StatCalc to foreground
    Minimize-ConsoleWindows
    Set-EpiInfoForeground | Out-Null
    Start-Sleep -Seconds 1

    # 6. Navigate to the Tables (2x2) view
    Write-Host "Navigating to Tables (2x2) view..."

    # StatCalc opens with a "Sample Size and Power" sub-window in front.
    # First click in the right portion of the main window (x=750, y=200) to bring
    # the main StatCalc navigation to the foreground.
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 750; y = 200; button = "left"} | Out-Null
    Start-Sleep -Milliseconds 600

    # Click the "TABLES (2 x 2 x N)" button in the left column of the navigation panel.
    # (coordinates verified on VM: left-column, 3rd row, approximately x=511, y=390)
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 511; y = 390; button = "left"} | Out-Null
    Start-Sleep -Seconds 2

    # Take screenshot to verify Tables view
    try {
        Invoke-PyAutoGUICommand -Command @{action = "screenshot"; path = "C:\Users\Docker\task_statcalc_tables.png"} | Out-Null
        Write-Host "Tables view screenshot saved"
    } catch { }

    # 7. Stop Edge killer
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== use_statcalc task setup complete ==="
    Write-Host "Epi Info 7 StatCalc is open on the Tables (2x2) view."
    Write-Host "Agent should enter: Exposed+Ill=20, Exposed+Not Ill=10, Unexposed+Ill=5, Unexposed+Not Ill=20 to calculate odds ratio."

} catch {
    Write-Host "ERROR in task setup: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
