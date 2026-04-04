#!/bin/bash
# Setup for: delete_repository task
set -e
echo "=== Setting up delete_repository task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi
echo "Artifactory is accessible."

# 2. Define variables
TARGET_REPO="helix-staging-local"
ARTIFACT_FILE="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
ARTIFACT_TARGET_PATH="$TARGET_REPO/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

# 3. Create the repository if it doesn't exist
# We use PUT to create/overwrite to ensure it exists and is clean
echo "Creating repository: $TARGET_REPO..."
art_api PUT "/api/repositories/$TARGET_REPO" \
'{
  "key": "'"$TARGET_REPO"'",
  "rclass": "local",
  "packageType": "generic",
  "description": "Helix project staging - TO BE DECOMMISSIONED"
}' > /dev/null

# 4. Deploy a real artifact to make the repo non-empty
# This simulates a real scenario where we are deleting data
if [ -f "$ARTIFACT_FILE" ]; then
    echo "Deploying artifact to $TARGET_REPO..."
    curl -s -u admin:password -X PUT -T "$ARTIFACT_FILE" \
        "http://localhost:8082/artifactory/$ARTIFACT_TARGET_PATH" > /dev/null
else
    echo "WARNING: Artifact file not found at $ARTIFACT_FILE. Creating dummy."
    echo "dummy content" > /tmp/dummy.jar
    curl -s -u admin:password -X PUT -T /tmp/dummy.jar \
        "http://localhost:8082/artifactory/$TARGET_REPO/dummy.jar" > /dev/null
fi

# 5. Record initial state for verification
# Verify target exists
if repo_exists "$TARGET_REPO"; then
    echo "true" > /tmp/initial_target_exists
else
    echo "false" > /tmp/initial_target_exists
    echo "ERROR: Failed to create target repository"
    exit 1
fi

# Verify default repo exists (we want to ensure agent doesn't delete the wrong one)
if repo_exists "example-repo-local"; then
    echo "true" > /tmp/initial_default_exists
else
    # Try to create it if missing (Artifactory OSS usually has it, but just in case)
    art_api PUT "/api/repositories/example-repo-local" \
    '{"key":"example-repo-local","rclass":"local","packageType":"generic"}' > /dev/null
    echo "true" > /tmp/initial_default_exists
fi

date +%s > /tmp/task_start_time.txt
echo "Initial setup verification complete."

# 6. Prepare UI
# Launch Firefox and navigate to home
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/"

# Wait a moment for rendering
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== delete_repository Setup Complete ==="