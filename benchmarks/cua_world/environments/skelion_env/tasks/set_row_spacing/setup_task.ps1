# setup_task.ps1 — set_row_spacing task
# Opens SketchUp with Solar_Project.skp, ready for agent to insert panels with 2.0m spacing

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up set_row_spacing task ==="

. C:\workspace\scripts\task_utils.ps1

# Kill browsers and any stale processes
Close-Browsers

# Ensure building model exists
Verify-SolarProjectExists | Out-Null

# Launch SketchUp with the project file (default 40s wait for plugins to load)
Reset-SketchUpModel

Write-Host "=== set_row_spacing task setup complete ==="
