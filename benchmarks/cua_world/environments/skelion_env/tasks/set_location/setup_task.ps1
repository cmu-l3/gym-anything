# setup_task.ps1 — set_location task
# Opens SketchUp with Solar_Project.skp, ready for agent to set geographic location

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up set_location task ==="

. C:\workspace\scripts\task_utils.ps1

# Kill browsers and any stale processes
Close-Browsers

# Ensure building model exists
Verify-SolarProjectExists | Out-Null

# Launch SketchUp with the project file (default 40s wait for plugins to load)
Reset-SketchUpModel

Write-Host "=== set_location task setup complete ==="
