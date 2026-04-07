# setup_task.ps1 — insert_solar_panels task
# Opens SketchUp with Solar_Project.skp, ready for agent to use Skelion

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up insert_solar_panels task ==="

. C:\workspace\scripts\task_utils.ps1

# Kill browsers and any stale processes
Close-Browsers

# Ensure building model exists
Verify-SolarProjectExists | Out-Null

# Launch SketchUp with the project file (default 40s wait for plugins to load)
Reset-SketchUpModel

Write-Host "=== insert_solar_panels task setup complete ==="
