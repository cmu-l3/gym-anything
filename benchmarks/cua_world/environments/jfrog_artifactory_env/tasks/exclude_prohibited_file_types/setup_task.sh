#!/bin/bash
echo "=== Setting up exclude_prohibited_file_types task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is accessible
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Ensure example-repo-local exists
# (It is default, but we verify)
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local not found. It should be auto-created by Artifactory OSS."
    # We cannot create it via API in OSS (Pro only), so we rely on the agent or environment
    echo "Proceeding, assuming agent might see it or it's a temporary API glitch."
fi

# Attempt to reset configuration for example-repo-local to defaults (remove excludes)
# Note: POST to update repo configuration might be restricted in OSS, but we attempt it to clean state.
# We set excludesPattern to empty string.
echo "Attempting to reset repository configuration..."
RESET_JSON='{"excludesPattern": ""}'
art_api POST "/api/repositories/example-repo-local" "$RESET_JSON" > /dev/null 2>&1 || true

# Start Firefox and navigate to the repository list
ensure_firefox_running "http://localhost:8082"
sleep 5
navigate_to "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="