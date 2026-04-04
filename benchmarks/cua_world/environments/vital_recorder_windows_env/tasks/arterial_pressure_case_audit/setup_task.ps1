# Setup script for arterial_pressure_case_audit task
# Launches Vital Recorder with an empty workspace.
# The agent must open each of the three .vital files independently
# to discover which contains ART monitoring data.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_art_audit.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up arterial_pressure_case_audit task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data directory and all three files exist
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    foreach ($caseNum in @("0001", "0002", "0003")) {
        $destFile = "$dataDir\$caseNum.vital"
        $srcFile  = "C:\workspace\data\$caseNum.vital"
        if (-not (Test-Path $destFile)) {
            if (Test-Path $srcFile) {
                Copy-Item $srcFile -Destination $destFile -Force
                Write-Host "Copied $caseNum.vital to VitalRecorderData"
            } else {
                Write-Host "WARNING: Source file not found: $srcFile"
            }
        } else {
            Write-Host "Data file already present: $destFile"
        }
    }

    # Remove any previous output files so agent starts clean
    $outputFiles = @(
        "C:\Users\Docker\Desktop\art_case_export.csv",
        "C:\Users\Docker\Desktop\art_audit_report.txt"
    )
    foreach ($f in $outputFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Host "Removed previous output: $f"
        }
    }

    # Record baseline state
    $baseline = @{
        timestamp              = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        data_dir               = $dataDir
        files_present          = @(Get-ChildItem $dataDir -Filter "*.vital" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        desktop_files_at_start = @(Get-ChildItem "C:\Users\Docker\Desktop" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    $baseline | ConvertTo-Json -Depth 4 | Out-File -FilePath "C:\Users\Docker\task_baseline_art_audit.json" -Encoding UTF8 -Force
    Write-Host "Baseline state recorded"

    # Launch Vital Recorder with empty workspace (NO file pre-loaded)
    # The agent must choose which files to open
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -WaitSeconds 22

    # Dismiss any startup dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_ArtAudit" -WaitSeconds 12
    }

    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder running with empty workspace - agent must discover which files have ART"
    } else {
        Write-Host "WARNING: Vital Recorder process not detected"
    }

    Write-Host "=== arterial_pressure_case_audit setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
