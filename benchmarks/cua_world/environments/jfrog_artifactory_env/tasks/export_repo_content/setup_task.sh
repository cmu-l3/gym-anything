#!/bin/bash
echo "=== Setting up Export Repo Content task ==="

source /workspace/scripts/task_utils.sh

# Record task start time immediately
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 2. Ensure example-repo-local exists
# (It is a default repo in OSS, so it should exist. If not, the task is harder but agent might create it.
# Ideally we assume the environment provides it as per env setup)

# 3. Deploy a real artifact to the repository so there is something to export
# We use curl to deploy the artifact via REST API
ARTIFACT_SOURCE="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
TARGET_REPO="example-repo-local"
TARGET_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
UPLOAD_URL="${ARTIFACTORY_URL}/artifactory/${TARGET_REPO}/${TARGET_PATH}"

if [ -f "$ARTIFACT_SOURCE" ]; then
    echo "Deploying commons-lang3 to ${TARGET_REPO}..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X PUT "$UPLOAD_URL" -T "$ARTIFACT_SOURCE")
    
    if [[ "$HTTP_CODE" =~ ^2 ]]; then
        echo "Artifact deployed successfully (HTTP $HTTP_CODE)"
    else
        echo "WARNING: Artifact deployment failed (HTTP $HTTP_CODE)"
    fi
else
    echo "WARNING: Source artifact not found at $ARTIFACT_SOURCE"
fi

# 4. Clean up any previous export directory to prevent false positives
if [ -d "/home/ga/repo_export" ]; then
    echo "Removing stale export directory..."
    rm -rf "/home/ga/repo_export"
fi

# 5. Launch Firefox pointing to Artifactory login or home
# We point to the specific admin page to help the agent, but they still need to login
echo "Starting Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/admin/artifactory/import_export"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="