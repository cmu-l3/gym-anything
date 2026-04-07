# setup_task.ps1 — shadow_study_panel_placement
# Resets model, records baseline, writes Denver solar reference data,
# then relaunches SketchUp for the agent.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up shadow_study_panel_placement task ==="

. C:\workspace\scripts\task_utils.ps1

Close-Browsers
Verify-SolarProjectExists | Out-Null

# Remove leftover files
Remove-Item "C:\Users\Docker\Desktop\Shadow_Analysis_Report.txt" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\baseline_comp_count.json"           -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\model_state_export.json"            -Force -ErrorAction SilentlyContinue

# Record task start timestamp (for is_new anti-gaming checks)
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts.txt" -Encoding ASCII -Force

# -------------------------------------------------------------------
# Step 1: Record baseline component count
# -------------------------------------------------------------------
$pluginsDir = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp\Plugins"

$baselineRuby = @'
require 'json'

def _sku_count_baseline(entities, depth = 0)
  n = 0
  entities.each do |e|
    if e.is_a?(Sketchup::ComponentInstance)
      n += 1
    elsif e.is_a?(Sketchup::Group) && depth < 8
      n += _sku_count_baseline(e.entities, depth + 1)
    end
  end
  n
rescue
  0
end

UI.start_timer(10.0, false) do
  begin
    model = Sketchup.active_model
    count = _sku_count_baseline(model.entities)
    File.open('C:/Users/Docker/baseline_comp_count.json', 'w') do |f|
      f.write(JSON.generate({ 'baseline' => count }))
    end
  rescue => e
    File.open('C:/Users/Docker/baseline_comp_count.json', 'w') do |f|
      f.write(JSON.generate({ 'baseline' => 0, 'error' => e.to_s }))
    end
  end
end
'@

$baselinePluginPath = Join-Path $pluginsDir "task_baseline_once.rb"
Set-Content -Path $baselinePluginPath -Value $baselineRuby -Encoding ASCII

$projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds 18

Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $baselinePluginPath -Force -ErrorAction SilentlyContinue

if (-not (Test-Path "C:\Users\Docker\baseline_comp_count.json")) {
    '{"baseline":0}' | Set-Content "C:\Users\Docker\baseline_comp_count.json" -Encoding UTF8
}
Write-Host "Baseline recorded"

# -------------------------------------------------------------------
# Step 2: Write Denver solar resource reference data
# -------------------------------------------------------------------
$denverSolarData = @"
DENVER, CO — SOLAR RESOURCE REFERENCE DATA
Site: Denver Elementary School District — Roof Survey
Coordinates: Latitude 39.5870 N, Longitude 104.7476 W
Elevation: 1,609 m (5,280 ft above sea level)

ANNUAL SOLAR RESOURCE (NREL PVWatts):
  Annual GHI: 5.31 kWh/m2/day
  Peak sun hours: 5.5 hours/day (annual average)
  Best months: May–August (>6.5 kWh/m2/day)
  Worst months: November–January (~3.8 kWh/m2/day)

SHADING CONSIDERATIONS:
  - Low winter sun angle (~27 degrees at solstice) causes extended morning/evening shadows
  - Rooftop HVAC units on north side may cast shadows in winter months
  - Recommended setback from north edge: 2.0 meters
  - Optimal tilt angle for Denver: 30 degrees (fixed mount)

TASK REQUIREMENTS:
  1. Set model location to Denver, CO (lat 39.5870 N, lon 104.7476 W)
  2. Place at least 40 solar panels using Skelion
  3. Document findings in Shadow_Analysis_Report.txt on the Desktop
     Report must include: site coordinates, panel count, shading summary
"@
Set-Content -Path "C:\Users\Docker\Desktop\denver_solar_data.txt" -Value $denverSolarData -Encoding UTF8

# -------------------------------------------------------------------
# Step 3: Relaunch SketchUp for agent
# -------------------------------------------------------------------
Reset-SketchUpModel

Write-Host "=== shadow_study_panel_placement task setup complete ==="
