#!/bin/bash
set -e
echo "=== Setting up change_admin_password task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Artifactory is accessible
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# 2. Verify Initial State: Old password MUST work
echo "Verifying initial credential state..."
INITIAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    "http://localhost:8082/artifactory/api/system/ping")

if [ "$INITIAL_STATUS" != "200" ]; then
    echo "ERROR: Initial state invalid. Admin password is not 'password' (HTTP $INITIAL_STATUS)."
    # Attempt to reset if possible, or fail
    exit 1
fi
echo "Initial state confirmed: Admin password is 'password' (HTTP 200)."

# Record this initial success for anti-gaming comparison
echo "$INITIAL_STATUS" > /tmp/initial_auth_status.txt

# 3. Prepare UI (Firefox)
# We navigate to the user profile page to give the agent a helpful start,
# but the agent must handle the login redirection if session is invalid.
TARGET_URL="http://localhost:8082/ui/admin/artifactory/security/users/admin/edit"
echo "Starting Firefox at $TARGET_URL..."

ensure_firefox_running "$TARGET_URL"
sleep 5
focus_firefox

# 4. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="