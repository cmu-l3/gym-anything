#!/bin/bash
# Setup for prevent_artifact_overwrite task
set -e

echo "=== Setting up prevent_artifact_overwrite task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 2. Ensure example-repo-local exists
# (It should exist by default in OSS, but we verify)
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local does not exist. Attempting to rely on default creation..."
    # We can't easily create it via API in OSS if it's missing, but setup_artifactory.sh checks for it.
fi

# 3. Ensure the target artifact exists (commons-io-2.15.1.jar)
ARTIFACT_PATH="org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
LOCAL_FILE="/home/ga/Desktop/commons-io-2.15.1.jar"

# If local file missing, create a dummy one
if [ ! -f "$LOCAL_FILE" ]; then
    echo "Creating dummy artifact file..."
    echo "Dummy Content" > "$LOCAL_FILE"
fi

echo "Deploying initial artifact to ensure it exists..."
# We use curl directly to upload
UPLOAD_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -X PUT \
    -T "$LOCAL_FILE" \
    "http://localhost:8082/artifactory/example-repo-local/$ARTIFACT_PATH")

echo "Initial upload HTTP status: $UPLOAD_HTTP"

if [[ "$UPLOAD_HTTP" != "201" && "$UPLOAD_HTTP" != "200" ]]; then
    echo "ERROR: Failed to upload initial artifact. HTTP $UPLOAD_HTTP"
    exit 1
fi

# 4. Verify that Overwrite is currently ALLOWED (Starting state check)
echo "Verifying initial state (Overwrite should be ALLOWED)..."
OVERWRITE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -X PUT \
    -d "Overwrite Test Content" \
    "http://localhost:8082/artifactory/example-repo-local/$ARTIFACT_PATH")

if [[ "$OVERWRITE_HTTP" == "200" || "$OVERWRITE_HTTP" == "201" ]]; then
    echo "Initial state verified: Overwrite is allowed (HTTP $OVERWRITE_HTTP)."
else
    echo "WARNING: Initial state incorrect. Overwrite returned HTTP $OVERWRITE_HTTP. Task may be trivial."
fi

# 5. Prepare the UI
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="