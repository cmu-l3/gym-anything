# setup_task.ps1 — school_district_title1_compliance
# Correct ordering: kill Excel -> delete stale files -> record Unix timestamp -> copy xlsx -> launch Excel.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_setup_school_district.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up school_district_title1_compliance ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils }

    # STEP 1: Kill running Excel
    Get-Process EXCEL -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # STEP 2: Delete stale output files BEFORE recording timestamp
    $destDir    = "C:\Users\Docker\Desktop\ExcelTasks"
    $dataFile   = "$destDir\school_district.xlsx"
    $resultJson = "C:\Users\Docker\school_district_title1_compliance_result.json"
    foreach ($f in @($dataFile, $resultJson)) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # STEP 3: Record Unix timestamp AFTER deleting stale files
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_school_district.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # STEP 4: Copy workbook from workspace to Desktop
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $srcFile = "C:\workspace\data\school_district.xlsx"
    if (-not (Test-Path $srcFile)) {
        Write-Host "ERROR: Source data file not found: $srcFile"; exit 1
    }
    Copy-Item $srcFile -Destination $dataFile -Force
    Write-Host "Data file ready at: $dataFile"

    # STEP 5: Launch Excel with the workbook
    try {
        $excelExe = Find-ExcelExe
        Launch-ExcelWorkbookInteractive -ExcelExe $excelExe -WorkbookPath $dataFile -WaitSeconds 14
        Dismiss-ExcelDialogsBestEffort -Retries 4 -InitialWaitSeconds 3
        Write-Host "Excel launched and dialogs dismissed."
    } catch {
        Write-Host "WARNING: Launch failed: $($_.Exception.Message)"
        $excelExe = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE"
        if (Test-Path $excelExe) {
            Start-Process -FilePath $excelExe -ArgumentList """$dataFile"""
            Start-Sleep -Seconds 8
        }
    }

    $proc = Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { Write-Host "Excel running (PID $($proc.Id))" }
    else        { Write-Host "WARNING: Excel process not detected." }

    Write-Host "=== Setup complete: school_district_title1_compliance ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
