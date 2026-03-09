#!/bin/bash
set -e
echo "=== Setting up download_artifact_from_repo task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
rm -rf /home/ga/Downloads
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

# 3. Verify source artifact exists locally (prepared by env setup)
SOURCE_FILE="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERROR: Source artifact not found at $SOURCE_FILE"
    # Fallback: create dummy if real one missing (should not happen in correct env)
    mkdir -p $(dirname "$SOURCE_FILE")
    dd if=/dev/zero of="$SOURCE_FILE" bs=1024 count=400
fi

# Calculate and store expected SHA256
EXPECTED_SHA256=$(sha256sum "$SOURCE_FILE" | cut -d' ' -f1)
echo "$EXPECTED_SHA256" > /tmp/expected_sha256.txt
echo "Expected SHA256: $EXPECTED_SHA256"

# 4. Deploy artifact to Artifactory 'example-repo-local'
echo "Deploying artifact to Artifactory..."
wait_for_artifactory 60

# Ensure repo exists (it's a default, but safe to check)
if ! repo_exists "example-repo-local"; then
    echo "Creating example-repo-local..."
    # Auto-creation usually handled by Artifactory, but we can rely on it being default
fi

# Deploy via REST API
TARGET_PATH="example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
DEPLOY_URL="${ARTIFACTORY_URL}/artifactory/${TARGET_PATH}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT \
    -T "$SOURCE_FILE" \
    "$DEPLOY_URL")

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo "Artifact deployed successfully."
else
    echo "ERROR: Failed to deploy artifact. HTTP $HTTP_CODE"
    exit 1
fi

# 5. Prepare Firefox
echo "Starting Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/repos/tree/General/example-repo-local"
sleep 5

# Focus window
focus_firefox

# 6. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="