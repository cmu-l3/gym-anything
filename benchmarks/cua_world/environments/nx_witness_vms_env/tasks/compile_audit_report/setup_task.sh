#!/bin/bash
set -e
echo "=== Setting up compile_audit_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Nx Server is running and accessible
wait_for_nx_server_ready() {
    local max_retries=30
    local count=0
    while [ $count -lt $max_retries ]; do
        if curl -sk "https://localhost:7001/rest/v1/system/info" --max-time 2 > /dev/null; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

if ! wait_for_nx_server_ready; then
    echo "ERROR: Nx Server not ready"
    # Try to restart?
    systemctl restart networkoptix-mediaserver || true
fi

# Authenticate and ensure token exists for the agent to potentially discover/use
# (Though the task expects them to authenticate themselves, ensuring the system is auth-ready is key)
refresh_nx_token > /dev/null 2>&1 || true

# Ensure Firefox is open to the documentation or web admin to give a hint of accessibility
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
sleep 5
maximize_firefox

# Clear any previous report
rm -f /home/ga/Documents/compliance_report.json

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="