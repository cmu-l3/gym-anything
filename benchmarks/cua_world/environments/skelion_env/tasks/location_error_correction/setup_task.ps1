# setup_task.ps1 — location_error_correction
# Seeds the model with London, UK coordinates (the "error"),
# records baseline component count, then relaunches for the agent.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up location_error_correction task ==="

. C:\workspace\scripts\task_utils.ps1

Close-Browsers
Verify-SolarProjectExists | Out-Null

Remove-Item "C:\Users\Docker\baseline_comp_count.json"  -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\model_state_export.json"   -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\location_seeded.txt"       -Force -ErrorAction SilentlyContinue

# Record task start timestamp (for is_new anti-gaming checks)
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts.txt" -Encoding ASCII -Force

$pluginsDir = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp\Plugins"

# -------------------------------------------------------------------
# Step 1: Seed LONDON coordinates + record baseline in one launch
# The Ruby plugin sets location to London, saves, then records baseline.
# -------------------------------------------------------------------
$seedAndBaselineRuby = @'
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

    # Set London, UK coordinates (the intentional error)
    si = model.shadow_info
    si['Latitude']  = 51.5074
    si['Longitude'] = -0.1278
    si['City']      = 'London'
    si['Country']   = 'United Kingdom'

    # Save the model so coordinates persist to the .skp file
    model.save

    # Record baseline component count
    count = _sku_count_baseline(model.entities)

    File.open('C:/Users/Docker/baseline_comp_count.json', 'w') do |f|
      f.write(JSON.generate({ 'baseline' => count, 'seeded_lat' => 51.5074, 'seeded_lon' => -0.1278 }))
    end
    File.open('C:/Users/Docker/location_seeded.txt', 'w') { |f| f.write('ok') }
  rescue => e
    File.open('C:/Users/Docker/baseline_comp_count.json', 'w') do |f|
      f.write(JSON.generate({ 'baseline' => 0, 'error' => e.to_s }))
    end
    File.open('C:/Users/Docker/location_seeded.txt', 'w') { |f| f.write("error: #{e}") }
  end
end
'@

$seedPluginPath = Join-Path $pluginsDir "task_seed_location_once.rb"
Set-Content -Path $seedPluginPath -Value $seedAndBaselineRuby -Encoding ASCII

# Launch SketchUp with plugin — it sets London + records baseline
$projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds 20

# Kill SketchUp and remove plugin
Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $seedPluginPath -Force -ErrorAction SilentlyContinue

# Verify seeding
if (-not (Test-Path "C:\Users\Docker\location_seeded.txt")) {
    Write-Host "WARNING: Location seeding may have failed"
}
if (-not (Test-Path "C:\Users\Docker\baseline_comp_count.json")) {
    '{"baseline":0,"seeded_lat":51.5074,"seeded_lon":-0.1278}' |
        Set-Content "C:\Users\Docker\baseline_comp_count.json" -Encoding UTF8
}
Write-Host "Seed result: done"
Write-Host "Baseline: recorded"

# -------------------------------------------------------------------
# Step 2: Write error report for the agent to reference
# -------------------------------------------------------------------
$errorReport = @"
LOCATION ERROR REPORT — SunBridge Energy
Date: 2025-11-14
Technician: Alex T.
Project: Peachtree Commerce Center, Atlanta, GA

ISSUE IDENTIFIED:
  The SketchUp model Solar_Project.skp has been set to the WRONG geographic
  location. The model currently shows London, United Kingdom as the site.

  INCORRECT location in model:
    City:      London, United Kingdom
    Latitude:  51.5074 N
    Longitude: 0.1278 W

  CORRECT location for this project:
    City:      Atlanta, Georgia, USA
    Latitude:  33.7490 N
    Longitude: 84.3880 W

IMPACT:
  London receives approximately 2.9 peak sun hours/day vs Atlanta's 4.9.
  Using London coordinates would underestimate generation by ~40%, making
  the system appear non-viable when it is actually cost-effective.

ACTION REQUIRED:
  1. Open SketchUp → Window → Model Info → Geo-location
     (or use Skelion's location interface) and correct the coordinates
     to Atlanta, GA: lat 33.7490 N, lon 84.3880 W.
  2. Place at least 50 solar panels using Skelion for the Atlanta site.
  3. Verify the corrected location is saved with the model.
"@
Set-Content -Path "C:\Users\Docker\Desktop\location_error_report.txt" -Value $errorReport -Encoding UTF8

# -------------------------------------------------------------------
# Step 3: Relaunch SketchUp for the agent (model now has London coords)
# -------------------------------------------------------------------
Reset-SketchUpModel

Write-Host "=== location_error_correction task setup complete ==="
