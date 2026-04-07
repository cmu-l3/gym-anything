# Note: This environment uses PowerShell. The file extension is .ps1 in the hooks, 
# but the content is provided here for the framework to write to the file.
# The filename in the code block header must match the expected extension for the environment (Windows).

# However, the output format requested implies using the provided headers. 
# I will provide the content suitable for a .ps1 file but labeled as setup_task.ps1.

<#
.SYNOPSIS
Setup script for configure_linux_server_audit task
#>

Write-Host "=== Setting up Linux Server Audit Task ==="

# 1. Create task start timestamp for anti-gaming
$startTime = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
Set-Content -Path "C:\workspace\task_start_time.txt" -Value $startTime

# 2. Ensure ADAudit Plus Service is running
$serviceName = "ManageEngineADAuditPlus"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service -eq $null) {
    Write-Host "Service not found, checking process..."
} elseif ($service.Status -ne 'Running') {
    Write-Host "Starting ADAudit Plus service..."
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 10
}

# 3. Wait for Web Port (8081 default)
Write-Host "Waiting for web interface..."
$retry = 0
while ($retry -lt 30) {
    $conn = Test-NetConnection -ComputerName localhost -Port 8081 -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host "Web interface is ready."
        break
    }
    Start-Sleep -Seconds 2
    $retry++
}

# 4. Launch Browser (Edge) to the login page
$url = "http://localhost:8081"
Write-Host "Launching browser to $url..."

# Stop existing instances to ensure clean state
Stop-Process -Name msedge -ErrorAction SilentlyContinue
Stop-Process -Name chrome -ErrorAction SilentlyContinue

# Start Edge
Start-Process "msedge" -ArgumentList $url,"--start-maximized","--new-window"

# 5. Wait for window and ensure focus (using simple timeout as PS has limited window control without external tools)
Start-Sleep -Seconds 5

# 6. Capture Initial Screenshot (using python/nircmd if available, or just placeholder if not)
# Assuming nircmd or similar is in path, or skipping if not available. 
# The framework usually handles screenshotting, but we'll try to drop a marker.
Write-Host "Setup complete. Browser launched."