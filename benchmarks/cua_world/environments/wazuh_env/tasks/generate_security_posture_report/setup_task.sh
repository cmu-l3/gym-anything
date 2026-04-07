#!/bin/bash
set -e
echo "=== Setting up generate_security_posture_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state: remove any existing report
rm -f /home/ga/security_posture_report.json 2>/dev/null || true

# Wait for Wazuh services to be fully ready before handing over to agent
echo "Checking service availability..."

# Check Manager API
if ! check_api_health; then
    echo "Waiting for Wazuh API..."
    wait_for_service "Wazuh API" "check_api_health" 180
fi

# Check Indexer API
if ! check_indexer_health; then
    echo "Waiting for Wazuh Indexer..."
    wait_for_service "Wazuh Indexer" "check_indexer_health" 180
fi

# Capture initial state for debugging (not strictly needed for verification as we check live state at end)
echo "Services represent ready state."

# Maximize a terminal window for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 2
fi

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="