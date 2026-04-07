# Setup script for mandm_conference_case_review task
# Opens Vital Recorder with 0001.vital loaded and creates output directory

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_mandm.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up mandm_conference_case_review task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data file exists
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    $dataFile = "$dataDir\0001.vital"
    if (-not (Test-Path $dataFile)) {
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        Copy-Item "C:\workspace\data\0001.vital" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Create output directory
    $outputDir = "C:\Users\Docker\Desktop\MandM"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # Remove any previous output files
    $outputFiles = @(
        "$outputDir\full_timeline.png",
        "$outputDir\induction_detail.png",
        "$outputDir\emergence_detail.png",
        "$outputDir\intraop_data.csv",
        "$outputDir\case_report.txt"
    )
    foreach ($f in $outputFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Host "Removed: $f"
        }
    }

    # Remove previous result files
    New-Item -ItemType Directory -Force -Path "C:\tmp" | Out-Null
    foreach ($p in @("C:\tmp\task_result_mandm.json", "C:\tmp\task_baseline_mandm.json")) {
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    }

    # Record baseline timestamp for verifier freshness check
    $baselinePath = "C:\tmp\task_baseline_mandm.json"
    $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $baselineJson = @{
        task_start_unix = $nowUnix
        task_start_iso  = (Get-Date -Format "o")
        case_file       = "0001.vital"
        output_dir      = $outputDir
    } | ConvertTo-Json -Depth 3
    $baselineJson | Out-File -FilePath $baselinePath -Encoding utf8 -Force
    Write-Host "Baseline timestamp recorded: $nowUnix"

    # Launch Vital Recorder with the data file
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_MandM" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with 0001.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== mandm_conference_case_review task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
