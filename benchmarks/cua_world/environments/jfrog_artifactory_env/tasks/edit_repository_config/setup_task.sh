#!/bin/bash
echo "=== Setting up edit_repository_config task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi
echo "Artifactory is accessible."

# Check if example-repo-local exists (it should by default)
echo "Verifying example-repo-local exists..."
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local does not exist. The task might be impossible."
    # We can't easily create it via REST in OSS if restricted, but let's try just in case
    # or rely on the agent to create it (though the task is to EDIT).
    # In standard OSS install, it exists.
fi

# Attempt to reset configuration to defaults (Best Effort)
# Note: PUT/POST might be restricted in OSS 7.x, so this might fail.
# If it fails, we assume the repo is in a passable state or accept that we can't fully clean it.
echo "Attempting to reset repository configuration..."
RESET_JSON='{
  "key": "example-repo-local",
  "rclass": "local",
  "packageType": "generic",
  "description": "",
  "includesPattern": "**/*",
  "excludesPattern": "",
  "notes": ""
}'

curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
     -X POST -H "Content-Type: application/json" \
     -d "$RESET_JSON" \
     "${ARTIFACTORY_URL}/artifactory/api/repositories/example-repo-local" > /dev/null 2>&1 || true

# Also try PUT
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
     -X PUT -H "Content-Type: application/json" \
     -d "$RESET_JSON" \
     "${ARTIFACTORY_URL}/artifactory/api/repositories/example-repo-local" > /dev/null 2>&1 || true

# Capture initial state of the repo for reference
get_repo_info "example-repo-local" > /tmp/initial_repo_state.json

# Prepare Firefox
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Focus and maximize
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="