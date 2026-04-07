# setup_task.ps1 — dcf_valuation_model
# Correct ordering: delete stale files -> record Unix timestamp -> copy xlsx -> launch Excel.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_setup_dcf_valuation.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up dcf_valuation_model ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils }

    # STEP 1: Kill running Excel
    Get-Process EXCEL -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # STEP 2: Delete stale output files BEFORE recording timestamp
    $destDir    = "C:\Users\Docker\Desktop\ExcelTasks"
    $dataFile   = "$destDir\company_valuation.xlsx"
    $resultJson = "C:\Users\Docker\dcf_valuation_model_result.json"
    foreach ($f in @($dataFile, $resultJson)) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # STEP 3: Record Unix timestamp AFTER deleting stale files
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_dcf_valuation.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # STEP 4: Copy workbook from workspace to Desktop
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $srcFile = "C:\workspace\data\company_valuation.xlsx"
    if (-not (Test-Path $srcFile)) {
        Write-Host "ERROR: Source data file not found: $srcFile"; exit 1
    }
    Copy-Item $srcFile -Destination $dataFile -Force
    Write-Host "Data file ready at: $dataFile"

    # STEP 5: Launch Excel with the workbook
    try {
        $excelExe = Find-ExcelExe
        Launch-ExcelDocumentInteractive -ExcelExe $excelExe -DocumentPath $dataFile -WaitSeconds 14
        Dismiss-ExcelDialogsBestEffort -Retries 4 -InitialWaitSeconds 3
        Write-Host "Excel launched and dialogs dismissed."
    } catch {
        Write-Host "WARNING: Launch failed: $($_.Exception.Message)"
        $excelExe = "C:\Program Files (x86)\Microsoft Office\Office14\EXCEL.EXE"
        if (Test-Path $excelExe) {
            Start-Process -FilePath $excelExe -ArgumentList """$dataFile"""
            Start-Sleep -Seconds 8
        }
    }

    $proc = Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { Write-Host "Excel running (PID $($proc.Id))" }
    else        { Write-Host "WARNING: Excel process not detected." }

    Write-Host "=== Setup complete: dcf_valuation_model ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
