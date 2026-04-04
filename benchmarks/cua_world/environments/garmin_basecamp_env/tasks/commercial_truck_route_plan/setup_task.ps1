# Setup script for commercial_truck_route_plan
# Transportation Dispatcher / Heavy Tractor-Trailer Truck Drivers ($399M GDP occupation)

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up commercial_truck_route_plan ==="

# Kill any stale BaseCamp or browser windows
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Close-BaseCamp

# STEP 1: Remove stale export file BEFORE recording timestamp (anti-gaming)
$desktopPath = "C:\Users\Docker\Desktop"
$staleGpx    = "$desktopPath\BostonFallRiver_FreightRoute.gpx"
Remove-Item $staleGpx -Force -ErrorAction SilentlyContinue
Write-Host "Removed stale GPX export (if any)."

# STEP 2: Clear BaseCamp library (task starts with empty library)
Clear-BaseCampData
Write-Host "BaseCamp library cleared (empty starting state)."

# STEP 3: Record task start timestamp AFTER cleanup
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Out-File -FilePath "C:\GarminTools\commercial_truck_route_plan_start_ts.txt" `
    -Encoding ASCII -Force
Write-Host "Task start timestamp recorded: $taskStart"

# STEP 4: Launch BaseCamp
$ready = Launch-BaseCampInteractive -WaitSeconds 80
if (-not $ready) {
    Write-Host "WARNING: BaseCamp may not have launched correctly"
}

# STEP 5: Close browsers (prevent distractions)
Close-Browsers

Write-Host "=== Setup Complete: commercial_truck_route_plan ==="
Write-Host "Starting state: empty BaseCamp library"
Write-Host "Task: create 7 waypoints + 1 delivery route + export as BostonFallRiver_FreightRoute.gpx"
