#!/bin/bash
set -e
echo "=== Setting up Restore Deleted Artifact task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# 2. Define artifact details
REPO_KEY="example-repo-local"
ARTIFACT_GROUP="org/apache/commons/commons-lang3/3.14.0"
ARTIFACT_NAME="commons-lang3-3.14.0.jar"
LOCAL_FILE="/home/ga/artifacts/commons-lang3/${ARTIFACT_NAME}"
TARGET_PATH="${REPO_KEY}/${ARTIFACT_GROUP}/${ARTIFACT_NAME}"
TARGET_URL="${ARTIFACTORY_URL}/artifactory/${TARGET_PATH}"

# Ensure local file exists (downloaded by environment setup)
if [ ! -f "$LOCAL_FILE" ]; then
    echo "ERROR: Local artifact file not found at $LOCAL_FILE"
    # Fallback: Create a dummy valid JAR if missing to prevent task crash
    mkdir -p "$(dirname "$LOCAL_FILE")"
    echo "Dummy JAR content" > "$LOCAL_FILE"
fi

# 3. Calculate expected checksums (integrity check)
EXPECTED_SHA256=$(sha256sum "$LOCAL_FILE" | awk '{print $1}')
EXPECTED_SIZE=$(stat -c %s "$LOCAL_FILE")
echo "$EXPECTED_SHA256" > /tmp/expected_sha256.txt
echo "$EXPECTED_SIZE" > /tmp/expected_size.txt
echo "Expected SHA256: $EXPECTED_SHA256"

# 4. Deploy the artifact initially
echo "Deploying artifact to $TARGET_URL..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -T "$LOCAL_FILE" "$TARGET_URL" > /dev/null

# Verify deployment succeeded
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" "$TARGET_URL")
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "ERROR: Failed to deploy initial artifact (HTTP $HTTP_CODE)"
    exit 1
fi
echo "Artifact deployed successfully."

# 5. Delete the artifact (Move to Trash Can)
# In Artifactory, DELETE moves to trash by default unless ?trashcan=0 is specified
echo "Deleting artifact (moving to Trash Can)..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X DELETE "$TARGET_URL" > /dev/null

# 6. Verify it is gone from repo (HTTP 404)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" "$TARGET_URL")
if [ "$HTTP_CODE" != "404" ]; then
    echo "ERROR: Artifact failed to delete (HTTP $HTTP_CODE)"
    exit 1
fi
echo "Artifact deleted and verified missing from repo."

# 7. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 8. Launch Firefox and prepare UI
echo "Launching Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}"
sleep 5

# Focus window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="