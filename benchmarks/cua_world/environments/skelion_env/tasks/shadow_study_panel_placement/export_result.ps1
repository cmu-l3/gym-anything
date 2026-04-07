# export_result.ps1 — shadow_study_panel_placement
# Saves model, extracts state via Ruby plugin, checks for TXT report.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for shadow_study_panel_placement ==="

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
# Step 2: Check for Shadow_Analysis_Report.txt (with is_new check)
# -------------------------------------------------------------------
$reportPath   = "C:\Users\Docker\Desktop\Shadow_Analysis_Report.txt"
$reportResult = Get-FileResult $reportPath
$reportContent = ""
if ($reportResult.exists) {
    $reportContent = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue
    Write-Host "Report found: $reportPath ($($reportResult.size_bytes) bytes, is_new=$($reportResult.is_new))"
} else {
    Write-Host "Report NOT found at $reportPath"
}

# -------------------------------------------------------------------
# Step 3: Kill SketchUp, inject export plugin
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
# Step 4: Read baseline and model export, build result
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
Write-Host "Baseline: $baseline | Final: $totalComps | Delta (panels): $panelDelta"
Write-Host "Model location: lat=$modelLat lon=$modelLon"

# -------------------------------------------------------------------
# Step 5: Write task result JSON
# -------------------------------------------------------------------
$result = [ordered]@{
    task               = "shadow_study_panel_placement"
    task_start         = $taskStart
    latitude           = $modelLat
    longitude          = $modelLon
    panel_delta        = $panelDelta
    total_comp_instances = $totalComps
    baseline_comp      = $baseline
    report_exists      = $reportResult.exists
    report_size_bytes  = $reportResult.size_bytes
    report_is_new      = $reportResult.is_new
    report_content     = $reportContent
    layer_names        = $layerNames
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\shadow_study_result.json" -Encoding UTF8
Write-Host "Result written to C:\Users\Docker\shadow_study_result.json"
Write-Host "=== Export complete ==="
