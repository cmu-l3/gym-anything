#!/bin/bash
# Setup for: enable_folder_download task
set -e

echo "=== Setting up enable_folder_download task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Artifactory
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 3. Ensure Artifacts are deployed to example-repo-local
# The agent needs something to download. We deploy commons-io manually here.
ARTIFACTS_SOURCE="/home/ga/Desktop"
REPO="example-repo-local"
GROUP_PATH="org/apache/commons/commons-io/2.15.1"
BASE_URL="http://localhost:8082/artifactory/${REPO}/${GROUP_PATH}"

echo "Deploying sample artifacts to ${REPO}..."

# Deploy JAR
if [ -f "${ARTIFACTS_SOURCE}/commons-io-2.15.1.jar" ]; then
    curl -u admin:password -X PUT "${BASE_URL}/commons-io-2.15.1.jar" \
         -T "${ARTIFACTS_SOURCE}/commons-io-2.15.1.jar" >/dev/null 2>&1
    echo "Deployed JAR"
else
    echo "WARNING: Source JAR not found at ${ARTIFACTS_SOURCE}, attempting fallback download..."
    # Fallback: Create dummy file if real one missing (shouldn't happen in this env)
    echo "dummy content" > /tmp/commons-io-2.15.1.jar
    curl -u admin:password -X PUT "${BASE_URL}/commons-io-2.15.1.jar" \
         -T "/tmp/commons-io-2.15.1.jar" >/dev/null 2>&1
fi

# Deploy POM (optional but realistic)
echo " <project>dummy pom</project>" > /tmp/dummy.pom
curl -u admin:password -X PUT "${BASE_URL}/commons-io-2.15.1.pom" \
     -T "/tmp/dummy.pom" >/dev/null 2>&1

# 4. Clear any previous output
rm -f "/home/ga/Desktop/commons-io-package.zip"

# 5. Start Firefox
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/artifactory/general_settings"
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="