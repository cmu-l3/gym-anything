# setup_task.ps1 — net_zero_system_design
# Resets model, records baseline, writes energy worksheet,
# then relaunches SketchUp for the agent.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up net_zero_system_design task ==="

. C:\workspace\scripts\task_utils.ps1

Close-Browsers
Verify-SolarProjectExists | Out-Null

Remove-Item "C:\Users\Docker\Desktop\System_Sizing_Report.txt" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\baseline_comp_count.json"         -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\model_state_export.json"          -Force -ErrorAction SilentlyContinue

# Record task start timestamp (for is_new anti-gaming checks)
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts.txt" -Encoding ASCII -Force

# -------------------------------------------------------------------
# Step 1: Record baseline component count via Ruby plugin
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
# Step 2: Write energy sizing worksheet
# -------------------------------------------------------------------
$worksheet = @"
ENERGY SIZING WORKSHEET — GreenCore Engineering
Project: Net-Zero Commercial Office Building
Location: Austin, TX
Coordinates: Latitude 30.4103 N, Longitude 97.8516 W

BUILDING ENERGY DEMAND:
  Annual consumption: 220,000 kWh/year
  Average monthly demand: 18,333 kWh/month
  Peak demand month: July (25,000 kWh — heavy AC load)

AUSTIN SOLAR RESOURCE (NREL PVWatts Data):
  Annual GHI: 5.50 kWh/m2/day
  Annual peak sun hours: 5.50 h/day
  System derate factor: 0.80 (accounting for inverter losses, wiring, soiling)

PANEL SPECIFICATIONS (SunPower SPR-400-WHT-D):
  Rated power (STC): 400 W per panel
  Panel area: 1.93 m2

NET-ZERO SIZING CALCULATION:
  Required annual generation = 220,000 kWh/year
  Daily generation needed = 220,000 / 365 = 602.7 kWh/day
  System DC size = 602.7 / (5.50 h * 0.80) = 136.97 kW DC
  Number of 400W panels = 136,970 W / 400 W = 342.4 → minimum 63 panels
  (NOTE: 63 panels is the MINIMUM required for demonstration purposes;
   a full net-zero system would require ~343 panels for this building.)

TASK INSTRUCTIONS:
  1. Set model location to Austin, TX (lat 30.4103 N, lon 97.8516 W)
  2. Place at least 63 solar panels on the roof using Skelion
  3. Create System_Sizing_Report.txt on Desktop with:
     - Site location and coordinates
     - Number of panels placed
     - Estimated annual generation (panels x 400W x 5.5h x 365 x 0.80)
     - Net-zero feasibility statement
"@
Set-Content -Path "C:\Users\Docker\Desktop\energy_worksheet.txt" -Value $worksheet -Encoding UTF8

# -------------------------------------------------------------------
# Step 3: Relaunch SketchUp for agent
# -------------------------------------------------------------------
Reset-SketchUpModel

Write-Host "=== net_zero_system_design task setup complete ==="
