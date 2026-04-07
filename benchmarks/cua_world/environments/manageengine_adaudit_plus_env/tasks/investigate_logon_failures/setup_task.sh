# Note: The environment is Windows, so this is actually a PowerShell script (setup_task.ps1)
# but the system expects the file content. I will provide the PS1 content.

Write-Host "=== Setting up Investigate Logon Failures task ==="

# 1. Create a timestamp for anti-gaming
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\workspace\task_start_time.txt" -Value $startTime

# 2. Simulate "Intruder" Logon Failures (Event ID 4625)
# We attempt to map a drive with a non-existent user multiple times to generate logs
Write-Host "Generating logon failure events for user 'intruder'..."
for ($i=1; $i -le 10; $i++) {
    $proc = Start-Process -FilePath "net.exe" -ArgumentList "use \\127.0.0.1\IPC$ /user:intruder wrongpassword$i" -NoNewWindow -PassThru -Wait
    Start-Sleep -Milliseconds 500
}
Write-Host "Logon failure events generated."

# 3. Ensure ADAudit Plus Service is running
$service = Get-Service -Name "ManageEngineADAuditPlus" -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne 'Running') {
    Write-Host "Starting ADAudit Plus service..."
    Start-Service -Name "ManageEngineADAuditPlus"
    # Wait for service startup (can be slow)
    Start-Sleep -Seconds 30
}

# 4. Open Edge to the Login Page
Write-Host "Launching Microsoft Edge..."
$url = "https://localhost:8081"
Start-Process "msedge" $url

# 5. Wait for window and maximize (using simple powershell window interaction if possible, 
# or relying on agent to handle focus. In this env, we ensure it's open).
Start-Sleep -Seconds 5

# 6. Capture Initial State Screenshot
# (Assuming a screenshot tool exists or using a powershell snippet if available. 
# If not, the framework typically handles pre-task screens, but we'll try a basic capture if tools exist.)
# In this environment, we'll skip complex PS screenshotting to avoid dependencies, 
# relying on the framework's hook system or simple existence checks.

Write-Host "=== Task setup complete ==="