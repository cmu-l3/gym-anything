#!/bin/bash
set -e
echo "=== Setting up move_artifact_to_prod task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 3. Clean up existing repositories to ensure fresh state
echo "Cleaning up repositories..."
delete_repo_if_exists "dev-libs-local"
delete_repo_if_exists "prod-libs-local"

# 4. Create source and destination repositories (Generic type)
echo "Creating repositories..."
# Create dev-libs-local
curl -s -u admin:password -X PUT \
    -H "Content-Type: application/json" \
    -d '{"rclass":"local","packageType":"generic"}' \
    "http://localhost:8082/artifactory/api/repositories/dev-libs-local" > /dev/null

# Create prod-libs-local
curl -s -u admin:password -X PUT \
    -H "Content-Type: application/json" \
    -d '{"rclass":"local","packageType":"generic"}' \
    "http://localhost:8082/artifactory/api/repositories/prod-libs-local" > /dev/null

# 5. Prepare artifact
ARTIFACT_SOURCE="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
if [ ! -f "$ARTIFACT_SOURCE" ]; then
    echo "ERROR: Artifact source not found at $ARTIFACT_SOURCE"
    # Fallback: create a dummy file if real one missing (shouldn't happen in correct env)
    mkdir -p /home/ga/artifacts/commons-lang3
    echo "Dummy Artifact Content" > "$ARTIFACT_SOURCE"
fi

# Calculate expected checksums
SHA256=$(sha256sum "$ARTIFACT_SOURCE" | awk '{print $1}')
SIZE=$(stat -c%s "$ARTIFACT_SOURCE")

echo "$SHA256" > /tmp/expected_sha256.txt
echo "$SIZE" > /tmp/expected_size.txt

# 6. Upload artifact to source repository
echo "Uploading artifact to dev-libs-local..."
TARGET_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
UPLOAD_URL="http://localhost:8082/artifactory/dev-libs-local/$TARGET_PATH"

curl -s -u admin:password -X PUT -T "$ARTIFACT_SOURCE" "$UPLOAD_URL" > /dev/null

# Verify upload
if curl -s -u admin:password -I "$UPLOAD_URL" | grep -q "200 OK"; then
    echo "Artifact uploaded successfully."
else
    echo "ERROR: Failed to upload artifact."
    exit 1
fi

# 7. Prepare Browser
echo "Launching Firefox..."
# Start Firefox pointing to the Artifact Browser for the source repo
ensure_firefox_running "http://localhost:8082/ui/repos/tree/General/dev-libs-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
sleep 5

# Focus and maximize
focus_firefox
sleep 2

# 8. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="