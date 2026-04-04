#!/bin/bash
echo "=== Setting up deploy_exploded_archive task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Download the specific Javadoc JAR to Desktop
JAVADOC_URL="https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0-javadoc.jar"
DEST_FILE="/home/ga/Desktop/commons-lang3-javadoc.jar"

echo "Downloading Javadoc JAR..."
if wget -q --timeout=60 "$JAVADOC_URL" -O "$DEST_FILE"; then
    echo "Download successful: $DEST_FILE"
    chown ga:ga "$DEST_FILE"
else
    echo "ERROR: Failed to download Javadoc JAR"
    exit 1
fi

# 2. Ensure Artifactory is running
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 3. Clean up any previous 'javadocs' folder in example-repo-local
# We assume 'javadocs' is the root folder for this task
echo "Cleaning up previous task artifacts..."
# Delete the specific path via API
# Note: In OSS, delete might need to be specific, or we use the recursive delete if available
# We'll attempt to delete the 'javadocs' folder.
art_api DELETE "/api/repositories/example-repo-local/javadocs" > /dev/null 2>&1 || true

# 4. Record initial state (should be empty/404)
echo "Recording initial state..."
INITIAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/storage/example-repo-local/javadocs/commons-lang3/index.html")
echo "$INITIAL_STATUS" > /tmp/initial_file_status.txt

# 5. Launch Firefox
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"

# 6. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="