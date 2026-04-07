# export_result.ps1 — permit_package_preparation
# Saves the working model, checks for Permit_Ready.skp on Desktop,
# extracts model state from the working model via Ruby plugin.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for permit_package_preparation ==="

. C:\workspace\scripts\task_utils.ps1

# Read task start timestamp for is_new checks
$taskStart = 0
$startTsFile = "C:\Users\Docker\task_start_ts.txt"
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}

function Get-FileResult {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        return [ordered]@{
            exists     = $true
            size_bytes = [long]$fi.Length
            mtime_unix = $mtime
            is_new     = ($mtime -gt $taskStart)
        }
    }
    return [ordered]@{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false }
}

# -------------------------------------------------------------------
# Step 1: Save current model (Ctrl+S — saves Solar_Project.skp)
# -------------------------------------------------------------------
$suProc = Get-Process SketchUp -ErrorAction SilentlyContinue
if ($suProc) {
    Write-Host "Saving model via Ctrl+S..."
    Send-PyAutoGUICommand -Command '{"action":"hotkey","keys":["ctrl","s"]}' | Out-Null
    Start-Sleep -Seconds 4
    Send-PyAutoGUICommand -Command '{"action":"press","key":"return"}' | Out-Null
    Start-Sleep -Seconds 2
}

# -------------------------------------------------------------------
# Step 2: Check for Permit_Ready.skp on Desktop (with is_new check)
# -------------------------------------------------------------------
$permitPath   = "C:\Users\Docker\Desktop\Permit_Ready.skp"
$permitResult = Get-FileResult $permitPath
Write-Host "Permit_Ready.skp check: exists=$($permitResult.exists), size=$($permitResult.size_bytes), is_new=$($permitResult.is_new)"

# -------------------------------------------------------------------
# Step 3: Kill SketchUp, run export plugin on the working Solar_Project.skp
# -------------------------------------------------------------------
Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$pluginsDir = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp\Plugins"
Remove-Item "C:\Users\Docker\model_state_export.json" -Force -ErrorAction SilentlyContinue

$exportRuby = @'
require 'json'

def _sku_count_export(entities, depth = 0)
  n = 0
  entities.each do |e|
    if e.is_a?(Sketchup::ComponentInstance)
      n += 1
    elsif e.is_a?(Sketchup::Group) && depth < 8
      n += _sku_count_export(e.entities, depth + 1)
    end
  end
  n
rescue
  0
end

UI.start_timer(10.0, false) do
  begin
    model = Sketchup.active_model
    si    = model.shadow_info
    result = {
      'latitude'             => (si['Latitude'].to_f  rescue 0.0),
      'longitude'            => (si['Longitude'].to_f rescue 0.0),
      'total_comp_instances' => _sku_count_export(model.entities),
      'layer_names'          => (model.layers.map(&:name) rescue []),
      'entity_count'         => model.entities.count
    }
    File.open('C:/Users/Docker/model_state_export.json', 'w') do |f|
      f.write(JSON.generate(result))
    end
  rescue => e
    File.open('C:/Users/Docker/model_state_export.json', 'w') do |f|
      f.write(JSON.generate({ 'error' => e.to_s }))
    end
  end
end
'@

$exportPluginPath = Join-Path $pluginsDir "task_export_once.rb"
Set-Content -Path $exportPluginPath -Value $exportRuby -Encoding ASCII

# Load the working model (Solar_Project.skp) to read model state
$projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds 18

Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $exportPluginPath -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# Step 4: Read baseline and model export
# -------------------------------------------------------------------
$baseline = 0
try {
    $baselineJson = Get-Content "C:\Users\Docker\baseline_comp_count.json" -Raw -ErrorAction Stop
    $baselineObj  = $baselineJson | ConvertFrom-Json
    $baseline     = [int]$baselineObj.baseline
} catch {
    Write-Host "WARNING: Could not read baseline; defaulting to 0"
}

$modelLat   = 0.0
$modelLon   = 0.0
$totalComps = 0
$layerNames = @()
try {
    $exportJson  = Get-Content "C:\Users\Docker\model_state_export.json" -Raw -ErrorAction Stop
    $exportObj   = $exportJson | ConvertFrom-Json
    $modelLat    = [double]$exportObj.latitude
    $modelLon    = [double]$exportObj.longitude
    $totalComps  = [int]$exportObj.total_comp_instances
    $layerNames  = $exportObj.layer_names
} catch {
    Write-Host "WARNING: Could not read model_state_export.json: $($_.Exception.Message)"
}

$panelDelta = [Math]::Max(0, $totalComps - $baseline)
Write-Host "Baseline: $baseline | Final: $totalComps | Delta: $panelDelta"
Write-Host "Location: lat=$modelLat lon=$modelLon"

# -------------------------------------------------------------------
# Step 5: Also extract Permit_Ready.skp model state if it exists
# -------------------------------------------------------------------
$permitLat   = $modelLat
$permitLon   = $modelLon
$permitComps = $totalComps

if ($permitResult.exists) {
    Remove-Item "C:\Users\Docker\permit_ready_export.json" -Force -ErrorAction SilentlyContinue

    $permitExportRuby = @'
require 'json'

def _sku_count_export(entities, depth = 0)
  n = 0
  entities.each do |e|
    if e.is_a?(Sketchup::ComponentInstance)
      n += 1
    elsif e.is_a?(Sketchup::Group) && depth < 8
      n += _sku_count_export(e.entities, depth + 1)
    end
  end
  n
rescue
  0
end

UI.start_timer(10.0, false) do
  begin
    model = Sketchup.active_model
    si    = model.shadow_info
    result = {
      'latitude'             => (si['Latitude'].to_f  rescue 0.0),
      'longitude'            => (si['Longitude'].to_f rescue 0.0),
      'total_comp_instances' => _sku_count_export(model.entities),
      'layer_names'          => (model.layers.map(&:name) rescue [])
    }
    File.open('C:/Users/Docker/permit_ready_export.json', 'w') do |f|
      f.write(JSON.generate(result))
    end
  rescue => e
    File.open('C:/Users/Docker/permit_ready_export.json', 'w') do |f|
      f.write(JSON.generate({ 'error' => e.to_s }))
    end
  end
end
'@
    Set-Content -Path $exportPluginPath -Value $permitExportRuby -Encoding ASCII
    Launch-SketchUpInteractive -FilePath $permitPath -WaitSeconds 18
    Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item $exportPluginPath -Force -ErrorAction SilentlyContinue

    try {
        $pExportJson = Get-Content "C:\Users\Docker\permit_ready_export.json" -Raw -ErrorAction Stop
        $pExport     = $pExportJson | ConvertFrom-Json
        $permitLat   = [double]$pExport.latitude
        $permitLon   = [double]$pExport.longitude
        $permitComps = [int]$pExport.total_comp_instances
        Write-Host "Permit_Ready.skp state: lat=$permitLat lon=$permitLon comps=$permitComps"
    } catch {
        Write-Host "WARNING: Could not read permit_ready_export.json"
    }
}

# Use best available data: prefer Permit_Ready.skp if it exists
$finalLat   = if ($permitResult.exists) { $permitLat } else { $modelLat }
$finalLon   = if ($permitResult.exists) { $permitLon } else { $modelLon }
$finalComps = if ($permitResult.exists) { $permitComps } else { $totalComps }
$finalDelta = [Math]::Max(0, $finalComps - $baseline)

# -------------------------------------------------------------------
# Step 6: Write task result JSON
# -------------------------------------------------------------------
$result = [ordered]@{
    task                = "permit_package_preparation"
    task_start          = $taskStart
    latitude            = $finalLat
    longitude           = $finalLon
    panel_delta         = $finalDelta
    total_comp_instances = $finalComps
    baseline_comp       = $baseline
    permit_file_exists  = $permitResult.exists
    permit_file_size    = $permitResult.size_bytes
    permit_file_is_new  = $permitResult.is_new
    working_model_lat   = $modelLat
    working_model_lon   = $modelLon
    working_panel_delta = $panelDelta
    layer_names         = $layerNames
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\permit_package_result.json" -Encoding UTF8
Write-Host "Result written to C:\Users\Docker\permit_package_result.json"
Write-Host "=== Export complete ==="
