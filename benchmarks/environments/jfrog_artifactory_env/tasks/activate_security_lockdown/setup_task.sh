#!/bin/bash
echo "=== Setting up activate_security_lockdown task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi

# Ensure Firefox is running and logged in
# We start at the Dashboard or Administration page
echo "Ensuring Firefox is running..."
ensure_firefox_running "http://localhost:8082/ui/admin/artifactory/general_settings"
sleep 5

# Maximize Firefox for visibility
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record initial configuration state (for debugging/verification context)
echo "Recording initial configuration..."
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/initial_config.xml 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Instructions:"
echo "1. Enable Offline Mode"
echo "2. Disable Anonymous Access"
echo "3. Set System Message to: SECURITY ALERT: System in Offline Lockdown"