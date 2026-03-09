Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_create_2x2_table.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up create_2x2_table task ==="

    # Source shared utilities
    . C:\workspace\scripts\task_utils.ps1

    # 1. Start Edge killer
    $edgeKiller = Start-EdgeKillerTask

    # 2. Kill existing Epi Info processes
    Close-Browsers
    Stop-EpiInfo

    # 3. Use EColi_classic.mdb flat-table dataset (ILLDUM, HAMBURGER, AGENUM, SEX, ONSETDATE)
    $ecoliClassicMdb = "C:\EpiInfo7\Projects\EColi\EColi_classic\EColi_classic.mdb"
    Write-Host "Using EColi classic dataset at: $ecoliClassicMdb"

    # 4. Launch Classic Analysis module directly
    Write-Host "Launching Epi Info 7 Classic Analysis (Analysis.exe)..."
    Launch-EpiInfoModuleInteractive -ModuleExe "Analysis.exe" -WaitSeconds 15

    # 5. Dismiss startup dialogs
    Dismiss-EpiInfoDialogs -Retries 3 -WaitSeconds 2

    # 6. Bring Classic Analysis to foreground by clicking its title bar (y~11)
    Write-Host "Focusing Classic Analysis window..."
    Start-Sleep -Seconds 1
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 200; y = 11} | Out-Null
        Start-Sleep -Milliseconds 500
    } catch { Write-Host "Title bar click failed (non-critical)" }

    # 7. Load EColi FoodHistory dataset via READ command
    Write-Host "Loading EColi FoodHistory dataset..."
    Start-Sleep -Seconds 1

    # Click in Program Editor text area at (778, 503)
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 778; y = 503} | Out-Null
    } catch { }
    Start-Sleep -Milliseconds 500

    # Clear program editor
    try {
        Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} | Out-Null
        Start-Sleep -Milliseconds 300
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "delete"} | Out-Null
        Start-Sleep -Milliseconds 300
    } catch { }

    # Type READ command using 'write' action (handles {, }, \, : special chars)
    $readCmd = "READ {$ecoliClassicMdb}:FoodHistory"
    Write-Host "Typing: $readCmd"
    try {
        Invoke-PyAutoGUICommand -Command @{action = "write"; text = $readCmd; interval = 0.03} | Out-Null
    } catch {
        Write-Host "write action failed: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 500

    # Click Run Commands button at (647, 396) to execute
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 647; y = 396} | Out-Null
    } catch { }
    Start-Sleep -Seconds 5

    # Take screenshot
    try {
        Invoke-PyAutoGUICommand -Command @{action = "screenshot"; path = "C:\Users\Docker\task_2x2_after_read.png"} | Out-Null
        Write-Host "Screenshot saved: task_2x2_after_read.png"
    } catch { }

    # 8. Stop Edge killer
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== create_2x2_table task setup complete ==="
    Write-Host "Epi Info 7 Classic Analysis is open with EColi classic dataset loaded (359 records, fields: ILLDUM HAMBURGER AGENUM SEX ONSETDATE)."
    Write-Host "Agent should run: TABLES HAMBURGER ILLDUM"

} catch {
    Write-Host "ERROR in task setup: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
