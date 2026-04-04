# Setup: mumps_vaccine_effectiveness_analysis
# Launches Epi Info Classic Analysis with Mumps dataset pre-loaded
# Agent must run FREQ, TABLES, LOGISTIC, ROUTEOUT, WRITE to complete the task

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up mumps_vaccine_effectiveness_analysis ==="

# Kill any existing Epi Info and browser processes
$edgeKiller = Start-EdgeKillerTask
Stop-EpiInfo
Close-Browsers
Start-Sleep -Seconds 2

# STEP 1: Delete stale output files (BEFORE recording timestamp)
$filesToClean = @(
    "C:\Users\Docker\mumps_analysis.html",
    "C:\Users\Docker\mumps_ve_summary.csv",
    "C:\Users\Docker\mumps_analysis.htm"
)
foreach ($f in $filesToClean) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}

# STEP 2: Record task start timestamp AFTER cleanup
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_mumps_ve.txt" -Encoding ASCII -Force

Write-Host "Task start timestamp: $ts"

# STEP 3: Verify the Mumps dataset exists
$mdbPath = "C:\EpiInfo7\Projects\Mumps\Mumps.mdb"
if (-not (Test-Path $mdbPath)) {
    Write-Host "WARNING: Mumps.mdb not found at expected path: $mdbPath"
    Write-Host "Searching for Mumps dataset..."
    $found = Get-ChildItem -Path "C:\EpiInfo7" -Filter "Mumps.mdb" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $mdbPath = $found.FullName
        Write-Host "Found Mumps.mdb at: $mdbPath"
    } else {
        Write-Host "ERROR: Mumps.mdb not found anywhere under C:\EpiInfo7"
    }
} else {
    Write-Host "Mumps.mdb found at: $mdbPath"
}

# STEP 4: Launch Classic Analysis module
Write-Host "Launching Classic Analysis..."
Launch-EpiInfoModuleInteractive -ModuleExe "Analysis.exe" -WaitSeconds 20

# Dismiss any dialogs (license, update, etc.)
Dismiss-EpiInfoDialogs -Retries 5 -WaitSeconds 3

Start-Sleep -Seconds 3

# STEP 5: Click on the program editor area and type the READ command
# The program editor is typically at these coordinates in Analysis.exe
Write-Host "Clicking program editor..."
Invoke-PyAutoGUICommand -Command @{action="click"; x=778; y=503}
Start-Sleep -Seconds 1

# Clear any existing content
Invoke-PyAutoGUICommand -Command @{action="hotkey"; keys=@("ctrl", "a")}
Start-Sleep -Seconds 0.5
Invoke-PyAutoGUICommand -Command @{action="key"; key="delete"}
Start-Sleep -Seconds 0.5

# Type READ command to load Mumps dataset
Write-Host "Loading Mumps dataset..."
$readCmd = "READ {$mdbPath}:Survey"
Invoke-PyAutoGUICommand -Command @{action="write"; text=$readCmd; interval=0.03}
Start-Sleep -Seconds 0.5

# Press Enter
Invoke-PyAutoGUICommand -Command @{action="key"; key="return"}
Start-Sleep -Seconds 0.5

# Type VARIABLES to show the agent what fields are available
Invoke-PyAutoGUICommand -Command @{action="write"; text="VARIABLES"; interval=0.03}
Start-Sleep -Seconds 0.5
Invoke-PyAutoGUICommand -Command @{action="key"; key="return"}
Start-Sleep -Seconds 0.5

# Click "Run Commands" button (or use F5 keyboard shortcut)
Write-Host "Running commands to load dataset..."
Invoke-PyAutoGUICommand -Command @{action="click"; x=647; y=396}
Start-Sleep -Seconds 5

Write-Host "Mumps dataset loaded and VARIABLES listed in output panel."

# STEP 6: Stop the edge killer
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== Setup Complete: mumps_vaccine_effectiveness_analysis ==="
Write-Host "Dataset: $mdbPath"
Write-Host "Table: Survey"
Write-Host "Agent should: READ, FREQ, TABLES, LOGISTIC, ROUTEOUT to mumps_analysis.html, WRITE to mumps_ve_summary.csv"
