#!/bin/bash
echo "=== Setting up Enable User Locking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory to be responsive
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# Reset Security Configuration to default (Locking Disabled) if needed
# We use the REST API to ensure a clean state.
# Note: Changing system config via REST API in OSS might be tricky with XML,
# but we can try to patch it or just assume default since it's a fresh env.
# For robustness, we record the initial state.

echo "Recording initial system configuration..."
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/initial_config.xml 2>/dev/null

# Ensure Firefox is running and logged in
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/artifactory/security/settings"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="