#!/bin/bash
set -e
echo "=== Setting up batch_deploy_archive task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 3. Clean up any previous state in the repository
# We want to ensure 'libs' directory doesn't exist in example-repo-local
echo "Cleaning up repository state..."
# Delete 'libs' folder if it exists (using artifacts delete API)
art_api DELETE "/example-repo-local/libs" >/dev/null 2>&1 || true

# 4. Prepare the ZIP archive on the Desktop
echo "Preparing migration-bundle.zip..."
WORK_DIR=$(mktemp -d)
mkdir -p "$WORK_DIR/libs"

# Source locations from env setup (setup_artifactory.sh downloads these)
SRC_LANG="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
SRC_IO="/home/ga/artifacts/commons-io/commons-io-2.15.1.jar"

# Verify source files exist, download if missing (robustness)
if [ ! -f "$SRC_LANG" ]; then
    echo "Downloading commons-lang3..."
    mkdir -p "$(dirname "$SRC_LANG")"
    wget -q -O "$SRC_LANG" "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
fi
if [ ! -f "$SRC_IO" ]; then
    echo "Downloading commons-io..."
    mkdir -p "$(dirname "$SRC_IO")"
    wget -q -O "$SRC_IO" "https://repo1.maven.org/maven2/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
fi

# Copy to structure
# Renaming to simpler names for the task description "libs/commons-lang3.jar"
cp "$SRC_LANG" "$WORK_DIR/libs/commons-lang3.jar"
cp "$SRC_IO" "$WORK_DIR/libs/commons-io.jar"

# Calculate checksums for verification later
sha1sum "$WORK_DIR/libs/commons-lang3.jar" | awk '{print $1}' > /tmp/expected_sha1_lang3.txt
sha1sum "$WORK_DIR/libs/commons-io.jar" | awk '{print $1}' > /tmp/expected_sha1_io.txt

# Create ZIP
pushd "$WORK_DIR" > /dev/null
zip -r migration-bundle.zip libs/
popd > /dev/null

# Move to Desktop
mkdir -p /home/ga/Desktop
mv "$WORK_DIR/migration-bundle.zip" /home/ga/Desktop/
chown ga:ga /home/ga/Desktop/migration-bundle.zip

# Cleanup
rm -rf "$WORK_DIR"

echo "Created /home/ga/Desktop/migration-bundle.zip"

# 5. Ensure Firefox is running and ready
ensure_firefox_running "http://localhost:8082"
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="