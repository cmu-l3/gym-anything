###############################################################################
# export_result.ps1 — post_task hook for topographic_plan_production
# Checks for DXF and .top project files, captures layer/entity info.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\task_topo_plan_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting topographic_plan_production results ==="

    $projDir   = "C:\Users\Docker\Desktop\ClearCreekProject"
    $dxfPath   = "$projDir\ClearCreek_TopoMap.dxf"
    $topPath   = "$projDir\ClearCreek.top"
    $resultPath = "C:\Users\Docker\topographic_plan_production_result.json"
    $startPath  = "C:\Users\Docker\topo_plan_start.txt"

    $startTimeStr = if (Test-Path $startPath) { Get-Content $startPath -Raw } else { "" }

    # --- DXF file ---
    $dxfExists  = Test-Path $dxfPath
    $dxfSize    = 0
    $dxfModTime = ""
    $lwpolyCount = 0
    $pointCount  = 0
    $hasLayerCurvas = $false
    $hasLayerPuntos = $false
    $hasLayerPerfil = $false

    # Search alternate names
    $altDxfPaths = @(
        "$projDir\ClearCreekTopoMap.dxf",
        "$projDir\topomap.dxf",
        "$projDir\mapa_topografico.dxf",
        "C:\Users\Docker\Desktop\ClearCreek_TopoMap.dxf"
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
            $dxfContent = Get-Content $dxfPath -Raw -Encoding utf8
            $lwpolyCount    = ([regex]::Matches($dxfContent, "LWPOLYLINE")).Count
            $pointCount     = ([regex]::Matches($dxfContent, "\bPOINT\b")).Count
            $hasLayerCurvas = $dxfContent -match "(?i)CURVAS"
            $hasLayerPuntos = $dxfContent -match "(?i)PUNTOS"
            $hasLayerPerfil = $dxfContent -match "(?i)PERFIL"
        } catch {
            # Large file — try stream approach
            try {
                $sr = [System.IO.StreamReader]::new($dxfPath, [System.Text.Encoding]::UTF8)
                $chunk = New-Object char[] 50000
                $read = $sr.Read($chunk, 0, 50000)
                $sr.Close()
                $partial = [string]::new($chunk, 0, $read)
                $lwpolyCount    = ([regex]::Matches($partial, "LWPOLYLINE")).Count
                $pointCount     = ([regex]::Matches($partial, "\bPOINT\b")).Count
                $hasLayerCurvas = $partial -match "(?i)CURVAS"
                $hasLayerPuntos = $partial -match "(?i)PUNTOS"
                $hasLayerPerfil = $partial -match "(?i)PERFIL"
            } catch {}
        }
    }

    # --- TopoCal .top project file ---
    $topExists  = Test-Path $topPath
    $topSize    = 0
    $topModTime = ""

    $altTopPaths = @(
        "$projDir\clearcreek.top",
        "$projDir\proyecto.top",
        "C:\Users\Docker\Desktop\ClearCreek.top"
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

    $result = [ordered]@{
        task_id           = "topographic_plan_production"
        start_time        = $startTimeStr.Trim()
        dxf_exists        = $dxfExists
        dxf_path          = $dxfPath
        dxf_size_bytes    = $dxfSize
        dxf_mod_time      = $dxfModTime
        dxf_lwpoly_count  = $lwpolyCount
        dxf_point_count   = $pointCount
        dxf_has_curvas    = $hasLayerCurvas
        dxf_has_puntos    = $hasLayerPuntos
        dxf_has_perfil    = $hasLayerPerfil
        top_exists        = $topExists
        top_path          = $topPath
        top_size_bytes    = $topSize
        top_mod_time      = $topModTime
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8
    Write-Host "Result written to $resultPath"
    Write-Host "  dxf=$dxfExists(${dxfSize}B) lwpoly=$lwpolyCount points=$pointCount  top=$topExists"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export: $_"
    @{ task_id="topographic_plan_production"; dxf_exists=$false; top_exists=$false; error=$_.ToString() } `
        | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\topographic_plan_production_result.json" -Encoding utf8
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
