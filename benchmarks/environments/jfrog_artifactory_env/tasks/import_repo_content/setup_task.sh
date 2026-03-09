#!/bin/bash
echo "=== Setting up import_repo_content task ==="

source /workspace/scripts/task_utils.sh

# ==============================================================================
# 1. Wait for Artifactory to be ready
# ==============================================================================
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# ==============================================================================
# 2. Clean Target Repository (example-repo-local)
#    We can't create a new repo via API in OSS, so we use the default one.
#    We clean it by deleting the specific artifact paths we expect to import.
# ==============================================================================
TARGET_REPO="example-repo-local"
echo "Cleaning target repository: $TARGET_REPO..."

# Delete specific paths if they exist to ensure a clean slate
art_api DELETE "/api/storage/$TARGET_REPO/org/apache/commons/commons-lang3" >/dev/null 2>&1 || true
art_api DELETE "/api/storage/$TARGET_REPO/org/apache/commons/commons-io" >/dev/null 2>&1 || true

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 3. Prepare Import Data on Filesystem
#    We need to construct a valid Maven repository layout in /home/ga/repo-import-data
# ==============================================================================
IMPORT_ROOT="/home/ga/repo-import-data"
ARTIFACTS_SOURCE="/home/ga/artifacts"

echo "Preparing import data at $IMPORT_ROOT..."
rm -rf "$IMPORT_ROOT"
mkdir -p "$IMPORT_ROOT"

# Define artifact details
LANG_VER="3.14.0"
LANG_PATH="org/apache/commons/commons-lang3/$LANG_VER"
IO_VER="2.15.1"
IO_PATH="org/apache/commons/commons-io/$IO_VER"

# Create directory structure
mkdir -p "$IMPORT_ROOT/$LANG_PATH"
mkdir -p "$IMPORT_ROOT/$IO_PATH"

# Copy Commons Lang 3
if [ -f "$ARTIFACTS_SOURCE/commons-lang3/commons-lang3-$LANG_VER.jar" ]; then
    cp "$ARTIFACTS_SOURCE/commons-lang3/commons-lang3-$LANG_VER.jar" "$IMPORT_ROOT/$LANG_PATH/"
    cp "$ARTIFACTS_SOURCE/commons-lang3/commons-lang3-$LANG_VER.pom" "$IMPORT_ROOT/$LANG_PATH/"
    echo "Prepared commons-lang3"
else
    echo "ERROR: Source artifacts for commons-lang3 not found!"
    exit 1
fi

# Copy Commons IO
if [ -f "$ARTIFACTS_SOURCE/commons-io/commons-io-$IO_VER.jar" ]; then
    cp "$ARTIFACTS_SOURCE/commons-io/commons-io-$IO_VER.jar" "$IMPORT_ROOT/$IO_PATH/"
    cp "$ARTIFACTS_SOURCE/commons-io/commons-io-$IO_VER.pom" "$IMPORT_ROOT/$IO_PATH/"
    echo "Prepared commons-io"
else
    echo "ERROR: Source artifacts for commons-io not found!"
    # Fallback to creating a dummy file if the source is missing (should not happen based on install script)
    echo "Creating dummy commons-io..."
    touch "$IMPORT_ROOT/$IO_PATH/commons-io-$IO_VER.jar"
    touch "$IMPORT_ROOT/$IO_PATH/commons-io-$IO_VER.pom"
fi

# Set permissions so Artifactory (running as ga/docker) can read it
chown -R ga:ga "$IMPORT_ROOT"
chmod -R 755 "$IMPORT_ROOT"

# ==============================================================================
# 4. Prepare UI State
# ==============================================================================
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 2

# Navigate specifically to Admin login or dashboard
navigate_to "http://localhost:8082/ui/login" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Import Path: $IMPORT_ROOT"
echo "Target Repo: $TARGET_REPO"