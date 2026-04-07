###############################################################################
# export_result.ps1 — post_task hook for site_complete_survey_analysis
# Captures all 4 deliverables: DXF, .top file (if saved), and analysis report.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\task_site_complete_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting site_complete_survey_analysis results ==="

    $projDir    = "C:\Users\Docker\Desktop\ElPasoSite"
    $dxfPath    = "$projDir\SiteAnalysis_ElPaso.dxf"
    $reportPath = "$projDir\SiteAnalysis.txt"
    $resultPath = "C:\Users\Docker\site_complete_survey_analysis_result.json"
    $startPath  = "C:\Users\Docker\site_complete_start.txt"
    $metaPath   = "C:\Users\Docker\site_complete_meta.json"

    $startTimeStr = if (Test-Path $startPath) { Get-Content $startPath -Raw } else { "" }

    # Read reference plane metadata from setup
    $lowerPlane = 0; $upperPlane = 0
    if (Test-Path $metaPath) {
        try {
            $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
            $lowerPlane = $meta.lower_plane
            $upperPlane = $meta.upper_plane
        } catch {}
    }

    # --- DXF file ---
    $dxfExists   = Test-Path $dxfPath
    $dxfSize     = 0
    $dxfModTime  = ""
    $lwpolyCount = 0
    $ptCount     = 0
    $hasCurvas   = $false
    $hasPuntos   = $false

    $altDxfPaths = @(
        "$projDir\SiteAnalysisElPaso.dxf",
        "$projDir\elpaso_topo.dxf",
        "$projDir\site_analysis.dxf",
        "C:\Users\Docker\Desktop\SiteAnalysis_ElPaso.dxf"
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
            $dxfContent  = Get-Content $dxfPath -Raw -Encoding utf8
            $lwpolyCount = ([regex]::Matches($dxfContent, "LWPOLYLINE")).Count
            $ptCount     = ([regex]::Matches($dxfContent, "\bPOINT\b")).Count
            $hasCurvas   = $dxfContent -match "(?i)CURVAS"
            $hasPuntos   = $dxfContent -match "(?i)PUNTOS"
        } catch {
            try {
                $sr = [System.IO.StreamReader]::new($dxfPath, [System.Text.Encoding]::UTF8)
                $buf = New-Object char[] 60000
                $read = $sr.Read($buf, 0, 60000)
                $sr.Close()
                $partial = [string]::new($buf, 0, $read)
                $lwpolyCount = ([regex]::Matches($partial, "LWPOLYLINE")).Count
                $ptCount     = ([regex]::Matches($partial, "\bPOINT\b")).Count
                $hasCurvas   = $partial -match "(?i)CURVAS"
                $hasPuntos   = $partial -match "(?i)PUNTOS"
            } catch {}
        }
    }

    # --- Analysis report ---
    $repExists  = Test-Path $reportPath
    $repSize    = 0
    $repModTime = ""
    $repContent = ""
    $repLines   = 0

    $altRepPaths = @(
        "C:\Users\Docker\Desktop\SiteAnalysis.txt",
        "$projDir\informe_sitio.txt",
        "$projDir\site_report.txt",
        "$projDir\analysis_report.txt"
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
        task_id           = "site_complete_survey_analysis"
        start_time        = $startTimeStr.Trim()
        lower_plane_m     = $lowerPlane
        upper_plane_m     = $upperPlane
        dxf_exists        = $dxfExists
        dxf_path          = $dxfPath
        dxf_size_bytes    = $dxfSize
        dxf_mod_time      = $dxfModTime
        dxf_lwpoly_count  = $lwpolyCount
        dxf_point_count   = $ptCount
        dxf_has_curvas    = $hasCurvas
        dxf_has_puntos    = $hasPuntos
        report_exists     = $repExists
        report_path       = $reportPath
        report_size_bytes = $repSize
        report_mod_time   = $repModTime
        report_lines      = $repLines
        report_content    = $repContent
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8
    Write-Host "Result written to $resultPath"
    Write-Host "  dxf=$dxfExists(${dxfSize}B) lwpoly=$lwpolyCount  report=$repExists lines=$repLines"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export: $_"
    @{ task_id="site_complete_survey_analysis"; dxf_exists=$false; report_exists=$false; error=$_.ToString() } `
        | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\site_complete_survey_analysis_result.json" -Encoding utf8
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
