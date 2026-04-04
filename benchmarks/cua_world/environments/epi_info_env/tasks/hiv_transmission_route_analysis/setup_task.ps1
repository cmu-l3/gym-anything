# Setup: hiv_transmission_route_analysis
# Launches Epi Info Classic Analysis with HIV dataset pre-loaded

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up hiv_transmission_route_analysis ==="

$edgeKiller = Start-EdgeKillerTask
Stop-EpiInfo
Close-Browsers
Start-Sleep -Seconds 2

# STEP 1: Delete stale output files (BEFORE recording timestamp)
$filesToClean = @(
    "C:\Users\Docker\hiv_transmission_analysis.html",
    "C:\Users\Docker\hiv_transmission_analysis.htm",
    "C:\Users\Docker\hiv_transmission_summary.csv"
)
foreach ($f in $filesToClean) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}

# STEP 2: Record task start timestamp AFTER cleanup
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_hiv_transmission.txt" -Encoding ASCII -Force

Write-Host "Task start timestamp: $ts"

# STEP 3: Verify the HIV dataset exists
$mdbPath = "C:\EpiInfo7\Projects\HIV\HIV.mdb"
if (-not (Test-Path $mdbPath)) {
    Write-Host "WARNING: HIV.mdb not found at expected path: $mdbPath"
    $found = Get-ChildItem -Path "C:\EpiInfo7" -Filter "HIV.mdb" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $mdbPath = $found.FullName
        Write-Host "Found HIV.mdb at: $mdbPath"
    } else {
        Write-Host "ERROR: HIV.mdb not found anywhere under C:\EpiInfo7"
    }
} else {
    Write-Host "HIV.mdb found at: $mdbPath"
}

# STEP 4: Launch Classic Analysis
Write-Host "Launching Classic Analysis..."
Launch-EpiInfoModuleInteractive -ModuleExe "Analysis.exe" -WaitSeconds 20
Dismiss-EpiInfoDialogs -Retries 5 -WaitSeconds 3
Start-Sleep -Seconds 3

# STEP 5: Load HIV dataset and show variables
Write-Host "Loading HIV dataset..."
Invoke-PyAutoGUICommand -Command @{action="click"; x=778; y=503}
Start-Sleep -Seconds 1

Invoke-PyAutoGUICommand -Command @{action="hotkey"; keys=@("ctrl", "a")}
Start-Sleep -Seconds 0.5
Invoke-PyAutoGUICommand -Command @{action="key"; key="delete"}
Start-Sleep -Seconds 0.5

$readCmd = "READ {$mdbPath}:Case"
Invoke-PyAutoGUICommand -Command @{action="write"; text=$readCmd; interval=0.03}
Start-Sleep -Seconds 0.3
Invoke-PyAutoGUICommand -Command @{action="key"; key="return"}
Start-Sleep -Seconds 0.3

Invoke-PyAutoGUICommand -Command @{action="write"; text="VARIABLES"; interval=0.03}
Start-Sleep -Seconds 0.3
Invoke-PyAutoGUICommand -Command @{action="key"; key="return"}
Start-Sleep -Seconds 0.3

Write-Host "Running READ and VARIABLES commands..."
Invoke-PyAutoGUICommand -Command @{action="click"; x=647; y=396}
Start-Sleep -Seconds 5

Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== Setup Complete: hiv_transmission_route_analysis ==="
Write-Host "Dataset: $mdbPath"
Write-Host "Table: Case"
Write-Host "Agent should run: FREQ, MEANS, TABLES, SELECT, ROUTEOUT, WRITE"
