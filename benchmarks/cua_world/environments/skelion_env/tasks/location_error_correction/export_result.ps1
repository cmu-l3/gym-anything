# export_result.ps1 — location_error_correction
# Saves model, extracts state via Ruby plugin, compares to seeded London coords.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for location_error_correction ==="

. C:\workspace\scripts\task_utils.ps1

# Read task start timestamp for is_new checks
$taskStart = 0
$startTsFile = "C:\Users\Docker\task_start_ts.txt"
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}

# -------------------------------------------------------------------
# Step 1: Save model (Ctrl+S)
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
# Step 2: Kill SketchUp, run export plugin
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

$projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds 18

Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $exportPluginPath -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# Step 3: Read baseline and model export, build result
# -------------------------------------------------------------------
$baseline   = 0
$seededLat  = 51.5074
$seededLon  = -0.1278
try {
    $baselineJson = Get-Content "C:\Users\Docker\baseline_comp_count.json" -Raw -ErrorAction Stop
    $baselineObj  = $baselineJson | ConvertFrom-Json
    $baseline     = [int]$baselineObj.baseline
    if ($baselineObj.seeded_lat) { $seededLat = [double]$baselineObj.seeded_lat }
    if ($baselineObj.seeded_lon) { $seededLon = [double]$baselineObj.seeded_lon }
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
Write-Host "Baseline: $baseline | Final: $totalComps | Delta (panels): $panelDelta"
Write-Host "Location: lat=$modelLat lon=$modelLon (was London: $seededLat, $seededLon)"

# -------------------------------------------------------------------
# Step 4: Write task result JSON
# -------------------------------------------------------------------
$result = [ordered]@{
    task               = "location_error_correction"
    task_start         = $taskStart
    latitude           = $modelLat
    longitude          = $modelLon
    panel_delta        = $panelDelta
    total_comp_instances = $totalComps
    baseline_comp      = $baseline
    seeded_lat         = $seededLat
    seeded_lon         = $seededLon
    layer_names        = $layerNames
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\location_correction_result.json" -Encoding UTF8
Write-Host "Result written to C:\Users\Docker\location_correction_result.json"
Write-Host "=== Export complete ==="
