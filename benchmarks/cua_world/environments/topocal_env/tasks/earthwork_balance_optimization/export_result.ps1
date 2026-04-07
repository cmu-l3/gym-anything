###############################################################################
# export_result.ps1 — post_task hook for earthwork_balance_optimization
# Captures grading_report.txt, site_grading.dxf, and site_grading.top
# and writes a result JSON that verifier.py can parse.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\task_earthwork_bal_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting earthwork_balance_optimization results ==="

    $projDir    = "C:\Users\Docker\Desktop\GradingStudy"
    $reportPath = "$projDir\grading_report.txt"
    $dxfPath    = "$projDir\site_grading.dxf"
    $topPath    = "$projDir\site_grading.top"
    $resultPath = "C:\Users\Docker\earthwork_balance_optimization_result.json"
    $startPath  = "C:\Users\Docker\earthwork_bal_start.txt"
    $metaPath   = "C:\Users\Docker\earthwork_bal_meta.json"

    # Read start time
    $startTimeStr = if (Test-Path $startPath) { Get-Content $startPath -Raw } else { "" }

    # Read metadata
    $metaContent = if (Test-Path $metaPath) { Get-Content $metaPath -Raw } else { "{}" }

    # ─── Report file ───
    $reportExists  = Test-Path $reportPath
    $reportSize    = 0
    $reportLines   = 0
    $reportContent = ""
    $reportModTime = ""

    # Check alternate locations
    $altReportPaths = @(
        "C:\Users\Docker\Desktop\grading_report.txt",
        "C:\Users\Docker\Documents\grading_report.txt",
        "$projDir\volume_report.txt",
        "$projDir\informe_terraplen.txt",
        "$projDir\earthwork_report.txt",
        "$projDir\balance_report.txt",
        "$projDir\optimization_report.txt"
    )
    if (-not $reportExists) {
        foreach ($alt in $altReportPaths) {
            if (Test-Path $alt) {
                $reportPath = $alt
                $reportExists = $true
                break
            }
        }
    }

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

    # ─── DXF file ───
    $dxfExists   = Test-Path $dxfPath
    $dxfSize     = 0
    $dxfModTime  = ""
    $lwpolyCount = 0
    $pointCount  = 0
    $hasLayerCurvas = $false

    # Check alternate locations
    $altDxfPaths = @(
        "$projDir\grading.dxf",
        "$projDir\terrain.dxf",
        "$projDir\contours.dxf",
        "C:\Users\Docker\Desktop\site_grading.dxf",
        "$projDir\curvas.dxf"
    )
    if (-not $dxfExists) {
        foreach ($alt in $altDxfPaths) {
            if (Test-Path $alt) { $dxfPath = $alt; $dxfExists = $true; break }
        }
    }

    if ($dxfExists) {
        $item = Get-Item $dxfPath
        $dxfSize    = $item.Length
        $dxfModTime = $item.LastWriteTime.ToString("o")
        try {
            $dxfContent     = Get-Content $dxfPath -Raw -Encoding utf8
            $lwpolyCount    = ([regex]::Matches($dxfContent, "LWPOLYLINE")).Count
            $pointCount     = ([regex]::Matches($dxfContent, "\bPOINT\b")).Count
            $hasLayerCurvas = $dxfContent -match "(?i)CURVAS"
        } catch {
            try {
                $sr = [System.IO.StreamReader]::new($dxfPath, [System.Text.Encoding]::UTF8)
                $chunk = New-Object char[] 50000
                $read = $sr.Read($chunk, 0, 50000)
                $sr.Close()
                $partial = [string]::new($chunk, 0, $read)
                $lwpolyCount    = ([regex]::Matches($partial, "LWPOLYLINE")).Count
                $pointCount     = ([regex]::Matches($partial, "\bPOINT\b")).Count
                $hasLayerCurvas = $partial -match "(?i)CURVAS"
            } catch {}
        }
    }

    # ─── TopoCal project file ───
    $topExists  = Test-Path $topPath
    $topSize    = 0
    $topModTime = ""

    $altTopPaths = @(
        "$projDir\grading.top",
        "$projDir\proyecto.top",
        "C:\Users\Docker\Desktop\site_grading.top",
        "$projDir\site_grading.tcp",
        "$projDir\site_grading.tcl"
    )
    if (-not $topExists) {
        foreach ($alt in $altTopPaths) {
            if (Test-Path $alt) { $topPath = $alt; $topExists = $true; break }
        }
    }

    if ($topExists) {
        $item = Get-Item $topPath
        $topSize    = $item.Length
        $topModTime = $item.LastWriteTime.ToString("o")
    }

    # ─── Build result JSON ───
    $result = [ordered]@{
        task_id            = "earthwork_balance_optimization"
        start_time         = $startTimeStr.Trim()
        metadata           = $metaContent.Trim()
        report_exists      = $reportExists
        report_path        = $reportPath
        report_size_bytes  = $reportSize
        report_lines       = $reportLines
        report_mod_time    = $reportModTime
        report_content     = $reportContent
        dxf_exists         = $dxfExists
        dxf_path           = $dxfPath
        dxf_size_bytes     = $dxfSize
        dxf_mod_time       = $dxfModTime
        dxf_lwpoly_count   = $lwpolyCount
        dxf_point_count    = $pointCount
        dxf_has_curvas     = $hasLayerCurvas
        top_exists         = $topExists
        top_path           = $topPath
        top_size_bytes     = $topSize
        top_mod_time       = $topModTime
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8

    Write-Host "Result written to $resultPath"
    Write-Host "  report=$reportExists(${reportSize}B, ${reportLines}L)"
    Write-Host "  dxf=$dxfExists(${dxfSize}B) lwpoly=$lwpolyCount points=$pointCount"
    Write-Host "  top=$topExists(${topSize}B)"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export: $_"
    @{ task_id="earthwork_balance_optimization"; report_exists=$false; dxf_exists=$false; top_exists=$false; error=$_.ToString() } `
        | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\earthwork_balance_optimization_result.json" -Encoding utf8
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
