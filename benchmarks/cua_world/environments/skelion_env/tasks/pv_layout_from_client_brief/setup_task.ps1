# setup_task.ps1 — pv_layout_from_client_brief
# Resets the model, records baseline component count, writes client brief,
# then relaunches SketchUp for the agent.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up pv_layout_from_client_brief task ==="

. C:\workspace\scripts\task_utils.ps1

Close-Browsers
Verify-SolarProjectExists | Out-Null

# Remove any leftover output files from previous runs
Remove-Item "C:\Users\Docker\Desktop\PV_Layout_Report.csv"  -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\baseline_comp_count.json"       -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\model_state_export.json"        -Force -ErrorAction SilentlyContinue

# Record task start timestamp (for is_new anti-gaming checks)
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts.txt" -Encoding ASCII -Force

# -------------------------------------------------------------------
# Step 1: Launch SketchUp with a baseline-recording Ruby plugin
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

# Launch SketchUp so plugin fires and records baseline
$projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds 18

# Kill SketchUp after plugin has had time to fire
Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Remove baseline plugin so it doesn't interfere with agent session
Remove-Item $baselinePluginPath -Force -ErrorAction SilentlyContinue

# Verify baseline was written
if (-not (Test-Path "C:\Users\Docker\baseline_comp_count.json")) {
    Write-Host "WARNING: baseline_comp_count.json not created; defaulting baseline to 0"
    '{"baseline":0}' | Set-Content "C:\Users\Docker\baseline_comp_count.json" -Encoding UTF8
}
Write-Host "Baseline recorded"

# -------------------------------------------------------------------
# Step 2: Write client brief on Desktop
# -------------------------------------------------------------------
$clientBrief = @"
CLIENT BRIEF — SunPath Solutions
Project: Commercial Rooftop PV System
Client: Harbor View Logistics Inc.
Site Address: 1 Harbor Way, San Francisco, CA 94107

SYSTEM REQUIREMENTS:
- Geographic location: San Francisco, CA (latitude 37.7314 N, longitude 122.3850 W)
- Panel orientation: Landscape
- Panel tilt angle: 5 degrees
- Row spacing: 1.5 meters
- Minimum panel count: 75 panels
- Deliverable: Export Skelion CSV project report as 'PV_Layout_Report.csv' on the Desktop

NOTES:
Use the Skelion plugin in SketchUp to insert panels with the above parameters.
After placing panels, use Skelion's report/export function to generate the CSV.
"@
Set-Content -Path "C:\Users\Docker\Desktop\client_brief.txt" -Value $clientBrief -Encoding UTF8

# -------------------------------------------------------------------
# Step 3: Relaunch SketchUp for the agent
# -------------------------------------------------------------------
Reset-SketchUpModel

Write-Host "=== pv_layout_from_client_brief task setup complete ==="
