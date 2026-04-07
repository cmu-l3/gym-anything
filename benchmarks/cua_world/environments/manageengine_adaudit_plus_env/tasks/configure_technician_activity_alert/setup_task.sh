# Note: This is a PowerShell script saved with a .ps1 extension in the environment.
# We present it here as setup_task.ps1 content.

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Configure Technician Activity Alert Task ==="

# 1. Record Task Start Time for Anti-Gaming
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\Windows\Temp\task_start_time.txt" -Value $startTime

# 2. Ensure ADAudit Plus Service is Running
Write-Host "Checking ADAudit Plus service..."
$serviceName = "ManageEngineADAuditPlus" # Adjust based on actual service name if different
try {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Running') {
        Write-Host "Starting ADAudit Plus service..."
        Start-Service -Name $serviceName
        # Wait for service to initialize (Java apps take time)
        Start-Sleep -Seconds 30
    } elseif (-not $service) {
        Write-Host "Service not found, assuming manual startup or different name. Proceeding..."
        # Fallback: Try running the startup script if available
        if (Test-Path "C:\Program Files\ManageEngine\ADAudit Plus\bin\run.bat") {
            Start-Process -FilePath "C:\Program Files\ManageEngine\ADAudit Plus\bin\run.bat" -WindowStyle Minimized
            Start-Sleep -Seconds 30
        }
    }
} catch {
    Write-Host "Warning: Could not check service status. Proceeding."
}

# 3. Close existing browsers to ensure clean state
Stop-Process -Name "msedge" -ErrorAction SilentlyContinue
Stop-Process -Name "chrome" -ErrorAction SilentlyContinue

# 4. Open Edge to the ADAudit Plus Login Page
Write-Host "Launching Microsoft Edge..."
$url = "http://localhost:8081"
Start-Process "msedge" $url
Start-Sleep -Seconds 5

# 5. Maximize Window (Simulated via shortcut or assuming agent handles it)
# In Windows containers, window management is limited, but we ensure the app is open.

Write-Host "=== Task Setup Complete ==="