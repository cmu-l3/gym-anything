#!/bin/bash
# Setup for: update_admin_profile task
echo "=== Setting up update_admin_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous run artifacts
echo "Cleaning up previous artifacts..."
rm -f /home/ga/encrypted_password.txt
rm -f /tmp/task_result.json

# 2. Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi

# 3. Ensure Firefox is running and logged in
# We start Firefox pointing to the home page
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/home"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Task: Update Admin Profile"
echo "1. Change admin email to: admin@example.com"
echo "2. Save Encrypted Password to: /home/ga/encrypted_password.txt"