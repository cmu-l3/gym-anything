# Note: This is a PowerShell script saved with .ps1 extension in the environment
# We output it here as setup_task.ps1 for clarity, but the system expects the content.

Write-Host "=== Setting up Restroom Exhaust Fan Retrofit Task ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$InpFile = "$ProjectDir\4StoreyBuilding.inp"
$StartTimeFile = "C:\tmp\task_start_time.txt"

# Create temp directory if not exists
New-Item -ItemType Directory -Force -Path "C:\tmp" | Out-Null

# Record task start time (Unix timestamp)
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path $StartTimeFile -Value $startTime
Write-Host "Task start time recorded: $startTime"

# Ensure eQUEST is running and window is maximized (handled by environment hooks usually, but good to ensure)
# We assume the environment starts with eQUEST open as per env definition.

# Backup the original INP file to ensure clean state if needed (optional, environment usually resets)
# But we can record the initial state of the zones for comparison if we wanted to be fancy.

Write-Host "=== Setup Complete ==="