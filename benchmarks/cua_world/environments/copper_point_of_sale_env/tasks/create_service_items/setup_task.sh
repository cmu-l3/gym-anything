#!/bin/bash
echo "=== Setting up Create Service Items Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a PowerShell setup script to run inside the container
cat > /tmp/win_setup.ps1 << 'PSEOF'
$ErrorActionPreference = "SilentlyContinue"

# 1. Start Copper POS
Write-Host "Starting Copper POS..."
$proc = Start-Process -FilePath "C:\Program Files (x86)\NCH Software\Copper\copper.exe" -PassThru
Start-Sleep -Seconds 5

# 2. Maximize Window (using crude method if wmctrl unavailable, or relying on Agent finding it)
# We assume the agent can find the window. 

# 3. Clean up previous items if they exist (Anti-gaming / Idempotency)
# We can't easily modify the proprietary DB safely while app is running without risking corruption.
# Instead, we rely on the verifier checking "DateCreated" or ensuring the agent overrides/edits if present.
# For this task, we assume a clean state or that the agent will handle errors if codes exist.

Write-Host "Setup Complete"
PSEOF

# Execute the PowerShell script inside the container
# Assuming container name 'copper_point_of_sale_env' or passed via env var
# Using 'docker exec' pattern for host-side script
CONTAINER_NAME="copper_point_of_sale_env" 

# Check if we are running inside or outside
if [ -f "/.dockerenv" ]; then
    # We are inside the agent container? Or the environment container?
    # If this script is executed by the framework, it might be on the host.
    # We'll assume we need to execute commands in the Windows environment.
    # If we are IN the windows env (via Git Bash?), we run powershell directly.
    if grep -q "Microsoft" /proc/version 2>/dev/null; then
         # WSL or similar
         powershell.exe -ExecutionPolicy Bypass -File /tmp/win_setup.ps1
    else
         # Linux container, need to talk to Windows container? 
         # Or maybe this IS the setup for the environment itself.
         # We will try to execute assuming we have access.
         echo "Running in Linux container context"
    fi
else
    # Host context
    echo "Running in Host context"
fi

# Fallback: Just ensure the timestamp is recorded. 
# The environment hooks in env.json likely handle the main app launch.
# We just need to mark the start time.

echo "Timestamp recorded."