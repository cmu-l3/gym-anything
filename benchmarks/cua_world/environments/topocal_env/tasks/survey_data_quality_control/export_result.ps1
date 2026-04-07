###############################################################################
# export_result.ps1 — post_task hook for survey_data_quality_control
# Captures cleaned_survey.csv row count and QC_Report.txt content.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\task_survey_qc_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting survey_data_quality_control results ==="

    $projDir     = "C:\Users\Docker\Desktop\BoulderQC"
    $cleanedPath = "$projDir\cleaned_survey.csv"
    $reportPath  = "$projDir\QC_Report.txt"
    $resultPath  = "C:\Users\Docker\survey_data_quality_control_result.json"
    $startPath   = "C:\Users\Docker\survey_qc_start.txt"

    $startTimeStr = if (Test-Path $startPath) { Get-Content $startPath -Raw } else { "" }

    # --- Cleaned CSV ---
    $csvExists  = Test-Path $cleanedPath
    $csvSize    = 0
    $csvModTime = ""
    $csvRows    = 0
    $csvPtNums  = @()  # collected point numbers from cleaned file

    # Also check alternate names
    $altCleanedPaths = @(
        "C:\Users\Docker\Desktop\cleaned_survey.csv",
        "$projDir\survey_clean.csv",
        "$projDir\puntos_limpios.csv",
        "$projDir\qc_survey.csv"
    )
    if (-not $csvExists) {
        foreach ($alt in $altCleanedPaths) {
            if (Test-Path $alt) { $cleanedPath = $alt; $csvExists = $true; break }
        }
    }

    if ($csvExists) {
        $item = Get-Item $cleanedPath
        $csvSize    = $item.Length
        $csvModTime = $item.LastWriteTime.ToString("o")
        try {
            $lines = Get-Content $cleanedPath -Encoding utf8
            # Count non-empty, non-header rows
            $dataRows = $lines | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "(?i)^point|^num|^id" }
            $csvRows = $dataRows.Count
            # Extract first column (point numbers) from first 200 rows
            foreach ($row in ($dataRows | Select-Object -First 200)) {
                $cols = $row -split ","
                if ($cols.Count -ge 1) {
                    $pt = $cols[0].Trim()
                    if ($pt -match "^\d+$") { $csvPtNums += [int]$pt }
                }
            }
        } catch {}
    }

    # --- QC Report ---
    $repExists  = Test-Path $reportPath
    $repSize    = 0
    $repModTime = ""
    $repContent = ""
    $repLines   = 0

    $altRepPaths = @(
        "C:\Users\Docker\Desktop\QC_Report.txt",
        "$projDir\informe_qc.txt",
        "$projDir\quality_control_report.txt"
    )
    if (-not $repExists) {
        foreach ($alt in $altRepPaths) {
            if (Test-Path $alt) { $reportPath = $alt; $repExists = $true; break }
        }
    }

    if ($repExists) {
        $item = Get-Item $reportPath
        $repSize    = $item.Length
        $repModTime = $item.LastWriteTime.ToString("o")
        try {
            $rawContent = Get-Content $reportPath -Raw -Encoding utf8
            $repContent = $rawContent -replace "`r`n", "\n" -replace "`r", "\n"
            $repLines   = ($rawContent -split "`n").Count
        } catch {}
    }

    $result = [ordered]@{
        task_id            = "survey_data_quality_control"
        start_time         = $startTimeStr.Trim()
        raw_point_count    = 150   # what setup created
        outlier_ids        = @(51, 52, 53, 54, 55, 56)
        cleaned_csv_exists = $csvExists
        cleaned_csv_path   = $cleanedPath
        cleaned_csv_size   = $csvSize
        cleaned_csv_mod    = $csvModTime
        cleaned_csv_rows   = $csvRows
        cleaned_pt_nums    = $csvPtNums
        report_exists      = $repExists
        report_path        = $reportPath
        report_size        = $repSize
        report_mod_time    = $repModTime
        report_lines       = $repLines
        report_content     = $repContent
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8
    Write-Host "Result written to $resultPath"
    Write-Host "  cleaned_csv=$csvExists rows=$csvRows  report=$repExists lines=$repLines"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export: $_"
    @{ task_id="survey_data_quality_control"; cleaned_csv_exists=$false; report_exists=$false; error=$_.ToString() } `
        | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\survey_data_quality_control_result.json" -Encoding utf8
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
