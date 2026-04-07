# setup_task.ps1 — permit_package_preparation
# Resets model, records baseline, writes NYC permit requirements document,
# then relaunches SketchUp for the agent.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up permit_package_preparation task ==="

. C:\workspace\scripts\task_utils.ps1

Close-Browsers
Verify-SolarProjectExists | Out-Null

Remove-Item "C:\Users\Docker\Desktop\Permit_Ready.skp"    -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\baseline_comp_count.json"    -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\model_state_export.json"     -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\permit_ready_export.json"    -Force -ErrorAction SilentlyContinue

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
# Step 2: Write NYC permit requirements document
# -------------------------------------------------------------------
$nycPermit = @"
NEW YORK CITY DEPARTMENT OF BUILDINGS
Solar Energy System Permit Requirements — Commercial Rooftop PV

PERMIT REFERENCE: DOB NOW: Build — Electrical Permit (1E-BC)
Applicable Code: NYC Energy Conservation Code (2020)

SITE INFORMATION REQUIRED:
  Project Location: New York City, NY
  Exact Coordinates: Latitude 40.7128 N, Longitude 74.0060 W

TECHNICAL SPECIFICATIONS FOR PERMIT PACKAGE:
  Panel Orientation: Landscape (per NYC fire setback rules — landscape allows 4ft pathways)
  Panel Tilt Angle: 10 degrees (maximum for ballasted flat-roof systems per NYC LL 77)
  Panel Count: Between 60 and 150 panels (to comply with building structural load limits)
  Fire Department Access: 6-foot setback from all roof edges required

FILE REQUIREMENTS:
  The permit package model must be saved as: Permit_Ready.skp
  Location: Desktop (C:\Users\Docker\Desktop\Permit_Ready.skp)
  This file is submitted to DOB for structural review.

WORKFLOW:
  1. Open Solar_Project.skp in SketchUp
  2. Window > Model Info > Geo-location: Set to NYC (lat 40.7128 N, lon 74.0060 W)
  3. In Skelion: Set orientation = Landscape, tilt = 10 degrees
  4. Use Skelion to insert between 60 and 150 panels on the flat roof
  5. File > Save As > type 'Permit_Ready' > save to Desktop
"@
Set-Content -Path "C:\Users\Docker\Desktop\nyc_permit_requirements.txt" -Value $nycPermit -Encoding UTF8

# -------------------------------------------------------------------
# Step 3: Relaunch SketchUp for agent
# -------------------------------------------------------------------
Reset-SketchUpModel

Write-Host "=== permit_package_preparation task setup complete ==="
