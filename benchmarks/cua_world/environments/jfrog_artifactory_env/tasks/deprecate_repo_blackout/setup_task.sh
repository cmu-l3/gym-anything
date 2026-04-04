#!/bin/bash
echo "=== Setting up Deprecate Repo Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 2. Ensure target repository exists
# Note: In OSS, we can't easily create repos via API, so we rely on the default 'example-repo-local'
# verifying it exists in the list.
echo "Verifying 'example-repo-local' exists..."
if ! repo_exists "example-repo-local"; then
    echo "WARNING: 'example-repo-local' not found. Task may fail if agent cannot edit it."
    # We cannot create it via API in OSS.
    # In a real scenario, we might fail here, but we'll proceed hoping it appears or the agent creates it (unlikely for this task).
else
    echo "Target repository found."
fi

# 3. Record Initial State (Anti-Gaming)
# We attempt to get the current config to ensure the agent actually changes it.
echo "Recording initial state..."
date +%s > /tmp/task_start_time.txt

# Try to get specific repo details (may fail in OSS, but good to try)
INITIAL_CONFIG=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories/example-repo-local")
echo "$INITIAL_CONFIG" > /tmp/initial_repo_config.json

# Also grab global config as backup source of truth
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/initial_system_config.xml

# 4. Prepare UI
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Focus window
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="