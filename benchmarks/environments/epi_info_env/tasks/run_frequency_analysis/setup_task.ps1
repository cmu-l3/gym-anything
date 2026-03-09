Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_run_frequency_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up run_frequency_analysis task ==="

    # Source shared utilities
    . C:\workspace\scripts\task_utils.ps1

    # 1. Start Edge killer to prevent browser popups
    $edgeKiller = Start-EdgeKillerTask

    # 2. Kill any existing Epi Info processes
    Close-Browsers
    Stop-EpiInfo

    # 3. Use EColi_classic.mdb flat-table dataset (ILLDUM, HAMBURGER, AGENUM, SEX, ONSETDATE)
    $ecoliClassicMdb = "C:\EpiInfo7\Projects\EColi\EColi_classic\EColi_classic.mdb"
    Write-Host "Using EColi classic dataset at: $ecoliClassicMdb"

    # 4. Launch Classic Analysis module directly (bypasses the hub)
    Write-Host "Launching Epi Info 7 Classic Analysis (Analysis.exe)..."
    Launch-EpiInfoModuleInteractive -ModuleExe "Analysis.exe" -WaitSeconds 15

    # 5. Dismiss any startup dialogs (license, update check, etc.)
    Dismiss-EpiInfoDialogs -Retries 3 -WaitSeconds 2

    # 6. Bring Classic Analysis window to foreground by clicking its title bar.
    #    The Analysis title bar is visible at the very top of the screen (y~11)
    #    even when the PyAutoGUI terminal is in the foreground.
    Write-Host "Focusing Classic Analysis window..."
    Start-Sleep -Seconds 1
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 200; y = 11} | Out-Null
        Start-Sleep -Milliseconds 500
    } catch { Write-Host "Title bar click failed (non-critical)" }

    # Take a screenshot to log the current state
    try {
        Invoke-PyAutoGUICommand -Command @{action = "screenshot"; path = "C:\Users\Docker\task_freq_before_read.png"} | Out-Null
        Write-Host "Screenshot saved: task_freq_before_read.png"
    } catch { Write-Host "Screenshot failed (non-critical)" }

    # 7. Load the EColi dataset via READ command
    Write-Host "Loading EColi dataset via READ command..."
    Start-Sleep -Seconds 1

    # Click in the Program Editor text area (bottom section of Classic Analysis window)
    # Program Editor text area is at approximately (278-1280, 415-590), center (778, 503)
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 778; y = 503} | Out-Null
    } catch { }
    Start-Sleep -Milliseconds 500

    # Clear the program editor (Ctrl+A then Delete)
    try {
        Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} | Out-Null
        Start-Sleep -Milliseconds 300
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "delete"} | Out-Null
        Start-Sleep -Milliseconds 300
    } catch { }

    # Type the READ command using 'write' action (handles special chars: {, }, \, :)
    $readCmd = "READ {$ecoliClassicMdb}:FoodHistory"
    Write-Host "Typing READ command: $readCmd"
    try {
        Invoke-PyAutoGUICommand -Command @{action = "write"; text = $readCmd; interval = 0.03} | Out-Null
    } catch {
        Write-Host "write action failed: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 500

    # Click "Run Commands" button to execute the READ command
    # Run Commands button is at approximately (647, 396) in the Program Editor toolbar
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 647; y = 396} | Out-Null
    } catch { }
    Start-Sleep -Seconds 5

    # 8. Screenshot after loading dataset
    try {
        Invoke-PyAutoGUICommand -Command @{action = "screenshot"; path = "C:\Users\Docker\task_freq_after_read.png"} | Out-Null
        Write-Host "Screenshot saved: task_freq_after_read.png"
    } catch { Write-Host "Screenshot failed (non-critical)" }

    # 9. Stop Edge killer task
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== run_frequency_analysis task setup complete ==="
    Write-Host "Epi Info 7 Classic Analysis is open with EColi classic dataset loaded (359 records, fields: ILLDUM HAMBURGER AGENUM SEX ONSETDATE)."
    Write-Host "Agent should run: FREQ ILLDUM"

} catch {
    Write-Host "ERROR in task setup: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
