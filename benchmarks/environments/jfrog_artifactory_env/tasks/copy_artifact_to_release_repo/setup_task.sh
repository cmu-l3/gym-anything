#!/bin/bash
set -e
echo "=== Setting up copy_artifact_to_release_repo task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure Artifactory is ready
# ============================================================
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# ============================================================
# 2. Setup Repositories (Clean State)
# ============================================================
SOURCE_REPO="staging-libs-local"
TARGET_REPO="release-libs-local"

echo "Recreating repositories..."
delete_repo_if_exists "$SOURCE_REPO"
delete_repo_if_exists "$TARGET_REPO"

# Create Source Repo (Generic)
art_api PUT "/api/repositories/$SOURCE_REPO" \
    '{"key":"'"$SOURCE_REPO"'","rclass":"local","packageType":"generic","description":"Staging repository for release candidates"}'

# Create Target Repo (Generic)
art_api PUT "/api/repositories/$TARGET_REPO" \
    '{"key":"'"$TARGET_REPO"'","rclass":"local","packageType":"generic","description":"Production release repository"}'

echo "Repositories created: $SOURCE_REPO, $TARGET_REPO"

# ============================================================
# 3. Deploy Artifacts to Source Repo
# ============================================================
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0"
LOCAL_SOURCE_DIR="/home/ga/artifacts/commons-lang3"

# Ensure local artifacts exist
if [ ! -f "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.jar" ]; then
    echo "ERROR: Local artifact source not found at $LOCAL_SOURCE_DIR"
    # Fallback: create dummy files if real ones failed to download in environment setup
    mkdir -p "$LOCAL_SOURCE_DIR"
    echo "dummy-jar" > "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.jar"
    echo "dummy-pom" > "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.pom"
fi

echo "Deploying artifacts to $SOURCE_REPO..."

# Deploy JAR
curl -s -u admin:password -T "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.jar" \
    "http://localhost:8082/artifactory/$SOURCE_REPO/$ARTIFACT_PATH/commons-lang3-3.14.0.jar"

# Deploy POM
curl -s -u admin:password -T "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.pom" \
    "http://localhost:8082/artifactory/$SOURCE_REPO/$ARTIFACT_PATH/commons-lang3-3.14.0.pom"

# Calculate and store checksums of source files
sha256sum "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.jar" | awk '{print $1}' > /tmp/source_jar_sha256.txt
sha256sum "$LOCAL_SOURCE_DIR/commons-lang3-3.14.0.pom" | awk '{print $1}' > /tmp/source_pom_sha256.txt

echo "Artifacts deployed to staging."

# ============================================================
# 4. Prepare UI
# ============================================================
ensure_firefox_running "http://localhost:8082/ui/packages"
sleep 5
# Navigate to the Artifacts browser which is the starting point for this task
navigate_to "http://localhost:8082/ui/repos/tree/General/$SOURCE_REPO"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="