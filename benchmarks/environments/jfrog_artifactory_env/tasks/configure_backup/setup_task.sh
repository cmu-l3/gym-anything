#!/bin/bash
echo "=== Setting up configure_backup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Record initial configuration state
# We fetch the system configuration XML to verify later that the backup didn't exist or was changed
echo "Recording initial system configuration..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /tmp/initial_config.xml

# Check if 'nightly-backup' already exists in the initial config (it shouldn't in a clean env)
if grep -q "<key>nightly-backup</key>" /tmp/initial_config.xml; then
    echo "WARNING: 'nightly-backup' already exists. This might affect verification."
else
    echo "Confirmed 'nightly-backup' does not exist."
fi

# Ensure Firefox is running and logged in
# We start at the Administration dashboard to save some steps, 
# but the agent still needs to find "Backups" under Services.
ensure_firefox_running "http://localhost:8082"
sleep 5

# Navigate to Admin dashboard
navigate_to "http://localhost:8082/ui/admin/artifactory/dashboard"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="