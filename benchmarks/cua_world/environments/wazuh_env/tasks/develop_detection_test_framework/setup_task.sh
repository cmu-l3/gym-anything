#!/bin/bash
set -e
echo "=== Setting up develop_detection_test_framework task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/validate_detections.py
rm -f /tmp/validation_output.txt
rm -f /tmp/task_result.json

# Ensure Wazuh manager is running and healthy
echo "Checking Wazuh manager health..."
wait_for_service "Wazuh API" "check_api_health" 60

# Ensure the logtest binary is executable inside container
echo "Verifying wazuh-logtest availability..."
if docker exec "${WAZUH_MANAGER_CONTAINER}" [ -x /var/ossec/bin/wazuh-logtest ]; then
    echo "wazuh-logtest found."
else
    echo "ERROR: wazuh-logtest not found or not executable in container."
    exit 1
fi

# Maximize terminal (since this is a coding task, agent likely uses terminal/IDE)
# We can't know which one, but we can ensure the environment is ready.
# Setup VSCode or simple editor if needed? The base env has vim/nano.
# We will just ensure the desktop is clean.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="