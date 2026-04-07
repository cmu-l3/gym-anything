# export_result.ps1 — pv_layout_from_client_brief
# Saves the SketchUp model, extracts model state via Ruby plugin,
# checks for the CSV report on Desktop, writes result JSON.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for pv_layout_from_client_brief ==="

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
# Step 1: Save the model (Ctrl+S) so panel changes persist to .skp
# -------------------------------------------------------------------
$suProc = Get-Process SketchUp -ErrorAction SilentlyContinue
if ($suProc) {
    Write-Host "Saving model via Ctrl+S..."
    Send-PyAutoGUICommand -Command '{"action":"hotkey","keys":["ctrl","s"]}' | Out-Null
    Start-Sleep -Seconds 4
    # Dismiss any save dialog that may appear
    Send-PyAutoGUICommand -Command '{"action":"press","key":"return"}' | Out-Null
    Start-Sleep -Seconds 2
}

# -------------------------------------------------------------------
# Step 2: Check Desktop for PV_Layout_Report.csv (with is_new check)
# -------------------------------------------------------------------
$csvPath = "C:\Users\Docker\Desktop\PV_Layout_Report.csv"
$csvResult = Get-FileResult $csvPath
Write-Host "CSV check: exists=$($csvResult.exists), size=$($csvResult.size_bytes), is_new=$($csvResult.is_new)"

# -------------------------------------------------------------------
# Step 3: Kill SketchUp, inject Ruby export plugin, relaunch
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

# Relaunch SketchUp to trigger plugin
$projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds 18

# Kill SketchUp
Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $exportPluginPath -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# Step 4: Read baseline and export JSON, build result
# -------------------------------------------------------------------
$baseline = 0
try {
    $baselineJson = Get-Content "C:\Users\Docker\baseline_comp_count.json" -Raw -ErrorAction Stop
    $baselineObj  = $baselineJson | ConvertFrom-Json
    $baseline     = [int]$baselineObj.baseline
} catch {
    Write-Host "WARNING: Could not read baseline; defaulting to 0"
}

$modelLat = 0.0
$modelLon = 0.0
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
Write-Host "Model location: lat=$modelLat lon=$modelLon"

# -------------------------------------------------------------------
# Step 5: Write task result JSON
# -------------------------------------------------------------------
$result = [ordered]@{
    task             = "pv_layout_from_client_brief"
    task_start       = $taskStart
    latitude         = $modelLat
    longitude        = $modelLon
    panel_delta      = $panelDelta
    total_comp_instances = $totalComps
    baseline_comp    = $baseline
    csv_exists       = $csvResult.exists
    csv_size_bytes   = $csvResult.size_bytes
    csv_is_new       = $csvResult.is_new
    layer_names      = $layerNames
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\pv_layout_result.json" -Encoding UTF8
Write-Host "Result written to C:\Users\Docker\pv_layout_result.json"
Write-Host "=== Export complete ==="
