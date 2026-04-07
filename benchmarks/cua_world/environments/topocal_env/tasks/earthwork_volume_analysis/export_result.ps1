###############################################################################
# export_result.ps1 — post_task hook for earthwork_volume_analysis
# Captures the volume_report.txt the agent produced and writes a result JSON
# that verifier.py can parse.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\task_earthwork_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting earthwork_volume_analysis results ==="

    $reportPath = "C:\Users\Docker\Desktop\JeffersonCountyProject\volume_report.txt"
    $resultPath = "C:\Users\Docker\earthwork_volume_analysis_result.json"
    $startPath  = "C:\Users\Docker\earthwork_va_start.txt"
    $refPath    = "C:\Users\Docker\earthwork_va_ref_plane.txt"

    # Read start time
    $startTimeStr = if (Test-Path $startPath) { Get-Content $startPath -Raw } else { "" }

    # Read reference plane
    $refPlane = if (Test-Path $refPath) { (Get-Content $refPath -Raw).Trim() } else { "0" }

    # Capture report metadata
    $reportExists = Test-Path $reportPath
    $reportSize   = 0
    $reportLines  = 0
    $reportContent = ""
    $reportModTime = ""

    if ($reportExists) {
        $item = Get-Item $reportPath
        $reportSize    = $item.Length
        $reportModTime = $item.LastWriteTime.ToString("o")
        try {
            $rawContent    = Get-Content $reportPath -Raw -Encoding utf8
            $reportContent = $rawContent -replace "`r`n", "\n" -replace "`r", "\n" -replace "`n", "\n"
            $reportLines   = ($rawContent -split "`n").Count
        } catch {
            $reportContent = ""
            $reportLines   = 0
        }
    }

    # Also check for alternate locations the agent might have used
    $altPaths = @(
        "C:\Users\Docker\Desktop\volume_report.txt",
        "C:\Users\Docker\Documents\volume_report.txt",
        "C:\Users\Docker\Desktop\JeffersonCountyProject\earthwork_report.txt",
        "C:\Users\Docker\Desktop\JeffersonCountyProject\informe_volumenes.txt"
    )
    $altFound = ""
    foreach ($alt in $altPaths) {
        if ((Test-Path $alt) -and -not $reportExists) {
            $altFound = $alt
            $item = Get-Item $alt
            $reportExists  = $true
            $reportSize    = $item.Length
            $reportModTime = $item.LastWriteTime.ToString("o")
            try {
                $rawContent    = Get-Content $alt -Raw -Encoding utf8
                $reportContent = $rawContent -replace "`r`n", "\n" -replace "`r", "\n"
                $reportLines   = ($rawContent -split "`n").Count
            } catch {}
            break
        }
    }

    # Capture survey CSV existence (shows import was done)
    $csvExists = Test-Path "C:\Users\Docker\Desktop\JeffersonCountyProject\site_survey.csv"

    # Build result object
    $result = [ordered]@{
        task_id         = "earthwork_volume_analysis"
        start_time      = $startTimeStr.Trim()
        ref_plane_m     = $refPlane
        report_exists   = $reportExists
        report_path     = if ($altFound) { $altFound } else { $reportPath }
        report_size_bytes = $reportSize
        report_lines    = $reportLines
        report_mod_time = $reportModTime
        report_content  = $reportContent
        survey_csv_exists = $csvExists
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8

    Write-Host "Result written to $resultPath"
    Write-Host "  report_exists=$reportExists  size=$reportSize  lines=$reportLines"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export: $_"
    # Write a minimal result so verifier can still run (and fail gracefully)
    @{ task_id="earthwork_volume_analysis"; report_exists=$false; error=$_.ToString() } `
        | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\earthwork_volume_analysis_result.json" -Encoding utf8
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
