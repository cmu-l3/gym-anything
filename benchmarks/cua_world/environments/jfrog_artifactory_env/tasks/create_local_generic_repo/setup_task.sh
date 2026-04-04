#!/bin/bash
set -e
echo "=== Setting up create_local_generic_repo task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 3. Clean up: Ensure the target repository does not exist
echo "Ensuring clean state..."
delete_repo_if_exists "build-artifacts-generic"

# 4. Ensure the source artifact exists on Desktop
# The environment installation script should have placed it there, but we verify/restore it.
ARTIFACT_SOURCE="/home/ga/Desktop/commons-lang3-3.14.0.jar"
BACKUP_SOURCE="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"

if [ ! -f "$ARTIFACT_SOURCE" ]; then
    echo "Restoring artifact to Desktop..."
    if [ -f "$BACKUP_SOURCE" ]; then
        cp "$BACKUP_SOURCE" "$ARTIFACT_SOURCE"
        chown ga:ga "$ARTIFACT_SOURCE"
    else
        echo "ERROR: Source artifact not found at $BACKUP_SOURCE"
        # Create a dummy file if real one is missing to prevent task crash (though verification will fail size check)
        echo "Dummy artifact" > "$ARTIFACT_SOURCE"
        chown ga:ga "$ARTIFACT_SOURCE"
    fi
fi

# 5. Record initial state (repo count)
INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count.txt

# 6. Prepare Firefox
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 5

# Navigate to home
navigate_to "http://localhost:8082/ui/packages"
sleep 2

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="