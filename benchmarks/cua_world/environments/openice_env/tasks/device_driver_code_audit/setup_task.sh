#!/bin/bash
echo "=== Setting up Device Driver Code Audit task ==="

source /workspace/scripts/task_utils.sh

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE is running (for GUI inspection part of task)
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any existing report from previous runs
rm -f /home/ga/Desktop/device_driver_audit.txt

# Ensure source code directory exists and is accessible
if [ ! -d "/opt/openice/mdpnp" ]; then
    echo "Error: Source code directory /opt/openice/mdpnp not found!"
    # Fallback: try to clone if missing (should be there from env setup)
    mkdir -p /opt/openice
    cd /opt/openice
    git clone --depth 1 https://github.com/mdpnp/mdpnp.git
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Source code location: /opt/openice/mdpnp"
echo "Expected output: /home/ga/Desktop/device_driver_audit.txt"