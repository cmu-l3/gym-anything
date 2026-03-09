#!/bin/bash
echo "=== Setting up Clean Repository Content task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure Artifactory is ready
# ============================================================
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory not accessible"
    exit 1
fi

# ============================================================
# 2. Prepare the Repository (example-repo-local)
# ============================================================
REPO_KEY="example-repo-local"

# Check if repo exists
if ! repo_exists "$REPO_KEY"; then
    echo "WARNING: $REPO_KEY does not exist. Attempting to create (if API allows) or fail."
    # In OSS, we can't create easily via API, but it should exist by default.
    # If missing, we can't proceed with this specific task target.
    echo "ERROR: Target repository $REPO_KEY missing and cannot be created via API in OSS."
    exit 1
fi

echo "Target repository $REPO_KEY exists."

# ============================================================
# 3. Populate Repository with Data to Clean
# ============================================================
echo "Populating repository with artifacts..."

# Define artifacts
ARTIFACT_1_SRC="/home/ga/Desktop/commons-lang3-3.14.0.jar"
ARTIFACT_1_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

ARTIFACT_2_SRC="/home/ga/Desktop/commons-io-2.15.1.jar"
ARTIFACT_2_PATH="commons-io/commons-io/2.15.1/commons-io-2.15.1.jar"

# Upload Artifact 1
if [ -f "$ARTIFACT_1_SRC" ]; then
    echo "Uploading $ARTIFACT_1_SRC..."
    curl -s -u admin:password -X PUT "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_1_PATH}" \
        -T "$ARTIFACT_1_SRC" > /dev/null
else
    echo "Creating dummy file for Artifact 1..."
    echo "dummy-content-1" > /tmp/dummy1.jar
    curl -s -u admin:password -X PUT "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_1_PATH}" \
        -T "/tmp/dummy1.jar" > /dev/null
fi

# Upload Artifact 2
if [ -f "$ARTIFACT_2_SRC" ]; then
    echo "Uploading $ARTIFACT_2_SRC..."
    curl -s -u admin:password -X PUT "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_2_PATH}" \
        -T "$ARTIFACT_2_SRC" > /dev/null
else
    echo "Creating dummy file for Artifact 2..."
    echo "dummy-content-2" > /tmp/dummy2.jar
    curl -s -u admin:password -X PUT "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_2_PATH}" \
        -T "/tmp/dummy2.jar" > /dev/null
fi

# ============================================================
# 4. Verify Initial State (Data IS present)
# ============================================================
echo "Verifying initial data presence..."
COUNT_BEFORE=$(curl -s -u admin:password "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO_KEY}?list&deep=1" | \
    grep -c "uri")
echo "Initial item count in $REPO_KEY: $COUNT_BEFORE"
echo "$COUNT_BEFORE" > /tmp/initial_item_count.txt

if [ "$COUNT_BEFORE" -lt 2 ]; then
    echo "WARNING: Failed to populate repository fully."
fi

# ============================================================
# 5. UI Setup
# ============================================================
# Start Firefox and navigate to the Artifact Browser (where the user works)
ensure_firefox_running "http://localhost:8082/ui/packages"
sleep 5
# Navigate specifically to the Tree Browser if possible, or just Home
navigate_to "http://localhost:8082/ui/artifactory/tree/artifacts/${REPO_KEY}"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="