###############################################################################
# export_result.ps1 — post_task hook for contour_gradient_analysis
# Captures contour_map.dxf and slope_analysis.txt, writes result JSON.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\task_contour_ga_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting contour_gradient_analysis results ==="

    $projDir      = "C:\Users\Docker\Desktop\GilpinProject"
    $dxfPath      = "$projDir\contour_map.dxf"
    $reportPath   = "$projDir\slope_analysis.txt"
    $resultPath   = "C:\Users\Docker\contour_gradient_analysis_result.json"
    $startPath    = "C:\Users\Docker\contour_ga_start.txt"

    $startTimeStr = if (Test-Path $startPath) { Get-Content $startPath -Raw } else { "" }

    # --- DXF file capture ---
    $dxfExists   = Test-Path $dxfPath
    $dxfSize     = 0
    $dxfModTime  = ""
    $dxfSnippet  = ""  # first 8000 chars for layer/entity analysis

    # Also search alternate paths
    $altDxfPaths = @(
        "C:\Users\Docker\Desktop\contour_map.dxf",
        "$projDir\GilpinContour.dxf",
        "$projDir\mapa_curvas.dxf"
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
            $dxfSnippet = (Get-Content $dxfPath -Raw -Encoding utf8 -TotalCount 500) -join "`n"
            if ($dxfSnippet.Length -gt 8000) { $dxfSnippet = $dxfSnippet.Substring(0, 8000) }
        } catch {
            # DXF may be large; read with a character limit
            try {
                $stream = [System.IO.StreamReader]::new($dxfPath, [System.Text.Encoding]::UTF8)
                $buf = New-Object char[] 8000
                $read = $stream.Read($buf, 0, 8000)
                $dxfSnippet = [string]::new($buf, 0, $read)
                $stream.Close()
            } catch { $dxfSnippet = "" }
        }
    }

    # Count LWPOLYLINE occurrences in DXF (each = one contour line)
    $lwpolyCount = 0
    $hasLayerCurvas1m = $false
    $hasLayerCurvas5m = $false
    if ($dxfExists) {
        try {
            $dxfFull = Get-Content $dxfPath -Raw -Encoding utf8
            $lwpolyCount = ([regex]::Matches($dxfFull, "LWPOLYLINE")).Count
            $hasLayerCurvas1m = $dxfFull -match "(?i)Curvas_1m|Curvas1m"
            $hasLayerCurvas5m = $dxfFull -match "(?i)Curvas_5m|Curvas5m"
        } catch {
            # File too large or binary — use snippet
            $lwpolyCount = ([regex]::Matches($dxfSnippet, "LWPOLYLINE")).Count
        }
    }

    # --- Slope analysis report capture ---
    $reportExists  = Test-Path $reportPath
    $reportSize    = 0
    $reportModTime = ""
    $reportLines   = 0
    $reportContent = ""

    $altReportPaths = @(
        "C:\Users\Docker\Desktop\slope_analysis.txt",
        "$projDir\analisis_pendientes.txt",
        "$projDir\gradient_report.txt"
    )
    if (-not $reportExists) {
        foreach ($alt in $altReportPaths) {
            if (Test-Path $alt) { $reportPath = $alt; $reportExists = $true; break }
        }
    }

    if ($reportExists) {
        $item = Get-Item $reportPath
        $reportSize    = $item.Length
        $reportModTime = $item.LastWriteTime.ToString("o")
        try {
            $rawContent    = Get-Content $reportPath -Raw -Encoding utf8
            $reportContent = $rawContent -replace "`r`n", "\n" -replace "`r", "\n"
            $reportLines   = ($rawContent -split "`n").Count
        } catch {}
    }

    $result = [ordered]@{
        task_id            = "contour_gradient_analysis"
        start_time         = $startTimeStr.Trim()
        dxf_exists         = $dxfExists
        dxf_path           = $dxfPath
        dxf_size_bytes     = $dxfSize
        dxf_mod_time       = $dxfModTime
        dxf_lwpoly_count   = $lwpolyCount
        dxf_has_curvas_1m  = $hasLayerCurvas1m
        dxf_has_curvas_5m  = $hasLayerCurvas5m
        report_exists      = $reportExists
        report_path        = $reportPath
        report_size_bytes  = $reportSize
        report_mod_time    = $reportModTime
        report_lines       = $reportLines
        report_content     = $reportContent
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8
    Write-Host "Result written to $resultPath"
    Write-Host "  dxf_exists=$dxfExists  lwpoly_count=$lwpolyCount  report_exists=$reportExists"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export: $_"
    @{ task_id="contour_gradient_analysis"; dxf_exists=$false; report_exists=$false; error=$_.ToString() } `
        | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\contour_gradient_analysis_result.json" -Encoding utf8
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
