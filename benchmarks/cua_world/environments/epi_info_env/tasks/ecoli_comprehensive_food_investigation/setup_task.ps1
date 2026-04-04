# Setup: ecoli_comprehensive_food_investigation
# Launches Epi Info Classic Analysis with EColi FoodHistory dataset pre-loaded
# Agent must run comprehensive attack rate tables + logistic regression + epidemic curve

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up ecoli_comprehensive_food_investigation ==="

$edgeKiller = Start-EdgeKillerTask
Stop-EpiInfo
Close-Browsers
Start-Sleep -Seconds 2

# STEP 1: Delete stale output files (BEFORE recording timestamp)
$filesToClean = @(
    "C:\Users\Docker\ecoli_food_investigation.html",
    "C:\Users\Docker\ecoli_food_investigation.htm",
    "C:\Users\Docker\ecoli_risk_factors.csv"
)
foreach ($f in $filesToClean) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}

# STEP 2: Record task start timestamp AFTER cleanup
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_ecoli_comprehensive.txt" -Encoding ASCII -Force

Write-Host "Task start timestamp: $ts"

# STEP 3: Locate the EColi dataset
$mdbPath = "C:\EpiInfo7\Projects\EColi\EColi.mdb"
if (-not (Test-Path $mdbPath)) {
    Write-Host "WARNING: EColi.mdb not found at $mdbPath, searching..."
    $found = Get-ChildItem -Path "C:\EpiInfo7" -Filter "EColi.mdb" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $mdbPath = $found.FullName
        Write-Host "Found EColi.mdb at: $mdbPath"
    }

    # Also check the EColi_classic path from existing setup scripts
    if (-not (Test-Path $mdbPath)) {
        $altPath = "C:\Users\Docker\Documents\EpiInfo\EColi_classic.mdb"
        if (Test-Path $altPath) {
            $mdbPath = $altPath
            Write-Host "Using EColi_classic.mdb at: $mdbPath"
        }
    }
} else {
    Write-Host "EColi.mdb found at: $mdbPath"
}

# STEP 4: Launch Classic Analysis
Write-Host "Launching Classic Analysis..."
Launch-EpiInfoModuleInteractive -ModuleExe "Analysis.exe" -WaitSeconds 20
Dismiss-EpiInfoDialogs -Retries 5 -WaitSeconds 3
Start-Sleep -Seconds 3

# STEP 5: Load EColi FoodHistory dataset and list variables
Write-Host "Loading EColi FoodHistory dataset..."
Invoke-PyAutoGUICommand -Command @{action="click"; x=778; y=503}
Start-Sleep -Seconds 1

Invoke-PyAutoGUICommand -Command @{action="hotkey"; keys=@("ctrl", "a")}
Start-Sleep -Seconds 0.5
Invoke-PyAutoGUICommand -Command @{action="key"; key="delete"}
Start-Sleep -Seconds 0.5

$readCmd = "READ {$mdbPath}:FoodHistory"
Invoke-PyAutoGUICommand -Command @{action="write"; text=$readCmd; interval=0.03}
Start-Sleep -Seconds 0.3
Invoke-PyAutoGUICommand -Command @{action="key"; key="return"}
Start-Sleep -Seconds 0.3

Invoke-PyAutoGUICommand -Command @{action="write"; text="VARIABLES"; interval=0.03}
Start-Sleep -Seconds 0.3
Invoke-PyAutoGUICommand -Command @{action="key"; key="return"}
Start-Sleep -Seconds 0.3

Write-Host "Running commands..."
Invoke-PyAutoGUICommand -Command @{action="click"; x=647; y=396}
Start-Sleep -Seconds 5

Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== Setup Complete: ecoli_comprehensive_food_investigation ==="
Write-Host "Dataset: $mdbPath"
Write-Host "Table: FoodHistory (359 records)"
Write-Host "Known food variables: HAMBURGER, HOTDOG, WATERMELON, LETTUCE, MUSTARD, RELISH, KETCHUP, ONION, PEPPERS, CORN, TOMATO, GROUNDMEAT"
Write-Host "Outcome variable: ILLDUM"
Write-Host "Agent must run: ROUTEOUT, FREQ *, TABLES for each food vs ILLDUM, LOGISTIC, WRITE"
