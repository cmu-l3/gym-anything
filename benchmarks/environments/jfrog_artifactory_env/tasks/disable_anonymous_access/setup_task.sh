#!/bin/bash
set -e
echo "=== Setting up task: disable_anonymous_access ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Artifactory is accessible
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# 2. Explicitly ENABLE anonymous access to guarantee the starting state
#    (We want the agent to actually do work, so we ensure it starts enabled)
echo "Ensuring anonymous access is ENABLED (initial state)..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -X PATCH \
  -H "Content-Type: application/yaml" \
  -d 'security:
  anonAccessEnabled: true' \
  "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /dev/null 2>&1

sleep 5

# 3. Verify initial state: unauthenticated access MUST work (HTTP 200)
ANON_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${ARTIFACTORY_URL}/artifactory/api/repositories" 2>/dev/null)

echo "Initial anonymous access status: HTTP ${ANON_STATUS}"
echo "${ANON_STATUS}" > /tmp/initial_anon_state.txt

if [ "$ANON_STATUS" != "200" ]; then
    echo "WARNING: Failed to enable anonymous access during setup. Setup may be flawed."
else
    echo "Confirmed: Anonymous access is currently ENABLED."
fi

# 4. Prepare UI
# Ensure Firefox is running and logged in/ready
ensure_firefox_running "${ARTIFACTORY_URL}/ui/login"
sleep 5

# Focus window
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="