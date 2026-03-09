#!/bin/bash
# Setup script for Manage Credentials task
# Ensures Jenkins is ready and no pre-existing credentials exist

echo "=== Setting up Manage Credentials Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Record initial credential count
echo "Recording initial credential state..."
INITIAL_CREDS=$(jenkins_api "credentials/store/system/domain/_/api/json" 2>/dev/null | jq '.credentials | length' 2>/dev/null || echo "0")
printf '%s' "$INITIAL_CREDS" > /tmp/initial_credential_count
echo "Initial credential count: $INITIAL_CREDS"

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Manage Credentials Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Navigate to 'Manage Jenkins' from the left sidebar or dashboard"
echo ""
echo "  2. Click on 'Credentials' in the Security section"
echo ""
echo "  3. Click on 'System' under Stores"
echo ""
echo "  4. Click on 'Global credentials (unrestricted)'"
echo ""
echo "  5. Click 'Add Credentials' and fill in:"
echo "     - Kind: Username with password"
echo "     - Username: deploy-user"
echo "     - Password: S3cureP@ss"
echo "     - ID: deploy-credentials"
echo "     - Description: Deployment server credentials"
echo ""
echo "  6. Click 'Create' to save"
echo ""
