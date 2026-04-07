# Setup: investigate_waterborne_outbreak
# Copies outbreak survey CSV to Documents, then launches Epi Info 7.
# Agent must open Classic Analysis, load the CSV, clean data, run analyses, and write report.

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up investigate_waterborne_outbreak ==="

# STEP 1: Delete stale output files (BEFORE recording timestamp)
$filesToClean = @(
    "C:\Users\Docker\Documents\outbreak_report.txt",
    "C:\Users\Docker\Documents\outbreak_report.htm",
    "C:\Users\Docker\Documents\outbreak_report.html",
    "C:\Users\Docker\Documents\outbreak_analysis.html",
    "C:\Users\Docker\Documents\outbreak_analysis.htm"
)
foreach ($f in $filesToClean) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}

# STEP 2: Record task start timestamp AFTER cleanup
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_waterborne.txt" -Encoding ASCII -Force

Write-Host "Task start timestamp: $ts"

# STEP 3: Copy outbreak survey CSV to Documents
$srcCsv = "C:\workspace\tasks\investigate_waterborne_outbreak\outbreak_survey.csv"
$dstCsv = "C:\Users\Docker\Documents\outbreak_survey.csv"

if (Test-Path $srcCsv) {
    Copy-Item $srcCsv $dstCsv -Force
    Write-Host "CSV copied to: $dstCsv"
} else {
    Write-Host "ERROR: Source CSV not found at $srcCsv"
}

# Verify the CSV
if (Test-Path $dstCsv) {
    $lineCount = (Get-Content $dstCsv | Measure-Object -Line).Lines
    Write-Host "CSV has $lineCount lines (expect 201: 1 header + 200 data rows)"
} else {
    Write-Host "ERROR: CSV not present at destination"
}

# STEP 4: Launch Epi Info 7 (main hub)
& C:\workspace\scripts\launch_app_pretask.ps1

Write-Host "=== Setup Complete: investigate_waterborne_outbreak ==="
Write-Host "Dataset: $dstCsv"
Write-Host "Agent must navigate to Classic Analysis, load the CSV, and perform the investigation"
