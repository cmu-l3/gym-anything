#!/bin/bash
echo "=== Setting up block_snapshot_artifacts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 2. Ensure example-repo-local exists and is clean (reset excludes pattern)
REPO_KEY="example-repo-local"
echo "Resetting configuration for $REPO_KEY..."

# Check if repo exists
if ! repo_exists "$REPO_KEY"; then
    echo "Creating default generic local repo: $REPO_KEY"
    # payload for generic local repo
    PAYLOAD='{"key":"'"$REPO_KEY"'","rclass":"local","packageType":"generic","description":"Example local repo","includesPattern":"**/*","excludesPattern":""}'
    art_api PUT "/api/repositories/$REPO_KEY" "$PAYLOAD"
else
    # Update existing repo to clear excludes pattern
    # We fetch current config to keep other settings, then patch excludesPattern
    # However, simplifying: just sending the update with empty excludes is easier if we know the type.
    # We'll assume generic or maven. Let's force it to be clean.
    PAYLOAD='{"key":"'"$REPO_KEY"'","rclass":"local","packageType":"generic","description":"Example local repo","includesPattern":"**/*","excludesPattern":""}'
    art_api POST "/api/repositories/$REPO_KEY" "$PAYLOAD"
fi

# Record initial config for debug
get_repo_info "$REPO_KEY" > /tmp/initial_repo_config.json

# 3. Prepare Firefox
# Open directly to the local repositories list to save time
TARGET_URL="http://localhost:8082/ui/admin/repositories/local"
ensure_firefox_running "$TARGET_URL"

# Wait for UI to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="