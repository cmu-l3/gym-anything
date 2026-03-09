#!/bin/bash
set -e
echo "=== Setting up Refactor Artifact Path Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Artifactory is running
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 3. Define paths and files
REPO_KEY="example-repo-local"
MISPLACED_PATH="misplaced/commons-io-2.15.1.jar"
TARGET_PATH="org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
LOCAL_FILE="/home/ga/Desktop/commons-io-2.15.1.jar"

# 4. Ensure we have the source file
if [ ! -f "$LOCAL_FILE" ]; then
    echo "Downloading commons-io-2.15.1.jar..."
    wget -q -O "$LOCAL_FILE" "https://repo1.maven.org/maven2/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
fi

# 5. Clean up destination (ensure target does NOT exist)
echo "Cleaning target path..."
curl -s -u admin:password -X DELETE \
    "http://localhost:8082/artifactory/${REPO_KEY}/${TARGET_PATH}" > /dev/null 2>&1 || true

# 6. Upload file to MISPLACED location (Start State)
echo "Uploading file to misplaced location..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password -T "$LOCAL_FILE" \
    "http://localhost:8082/artifactory/${REPO_KEY}/${MISPLACED_PATH}")

if [ "$HTTP_CODE" -ne 201 ] && [ "$HTTP_CODE" -ne 200 ]; then
    echo "ERROR: Failed to upload initial artifact. HTTP code: $HTTP_CODE"
    exit 1
fi

# 7. Start Firefox and navigate to the Artifact Browser
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/repos/tree/General/${REPO_KEY}/misplaced"

# 8. Capture initial state
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Artifact uploaded to: ${REPO_KEY}/${MISPLACED_PATH}"
echo "Goal: Move to ${REPO_KEY}/${TARGET_PATH}"