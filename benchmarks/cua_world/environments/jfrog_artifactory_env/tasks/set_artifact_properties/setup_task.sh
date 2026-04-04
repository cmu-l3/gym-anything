#!/bin/bash
set -e
echo "=== Setting up set_artifact_properties task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Verify Artifactory is ready
echo "Waiting for Artifactory..."
wait_for_artifactory 120 || { echo "Artifactory not ready"; exit 1; }

# 2. Ensure example-repo-local exists (it should be default, but verify)
if ! repo_exists "example-repo-local"; then
    echo "Creating example-repo-local..."
    # In OSS we can't easily create via REST without valid JSON, 
    # but the environment setup script guarantees it exists or warns.
    # If missing here, we might fail, but let's try to proceed.
    echo "WARNING: example-repo-local not found in list, attempting upload anyway (might fail if repo missing)"
fi

# 3. Prepare the artifact file
ARTIFACT_SOURCE="/home/ga/Desktop/commons-lang3-3.14.0.jar"
TARGET_PATH="example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
UPLOAD_URL="${ARTIFACTORY_URL}/artifactory/${TARGET_PATH}"

if [ ! -f "$ARTIFACT_SOURCE" ]; then
    echo "Downloading artifact source..."
    wget -q -O "$ARTIFACT_SOURCE" "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
fi

# 4. Upload the artifact (PUT)
echo "Uploading artifact to $TARGET_PATH..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT \
    -T "$ARTIFACT_SOURCE" \
    "$UPLOAD_URL")

if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: Failed to upload artifact. HTTP $HTTP_CODE"
    exit 1
fi
echo "Artifact uploaded successfully."

# 5. Ensure NO properties are set (Clean state)
# Delete properties endpoint: DELETE /api/storage/{path}?properties
echo "Clearing any existing properties..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X DELETE \
    "${ARTIFACTORY_URL}/artifactory/api/storage/${TARGET_PATH}?properties" > /dev/null 2>&1 || true

# 6. Open Firefox to the Artifact Browser
echo "Launching Firefox..."
# Direct link to the artifact browser for the repo
BROWSER_URL="${ARTIFACTORY_URL}/ui/repos/tree/General/example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

ensure_firefox_running "$BROWSER_URL"
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="