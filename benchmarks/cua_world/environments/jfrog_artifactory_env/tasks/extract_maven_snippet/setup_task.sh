#!/bin/bash
set -e
echo "=== Setting up extract_maven_snippet task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Artifactory is accessible
wait_for_artifactory 60

# 3. Clean up previous run artifacts
rm -f /home/ga/Desktop/maven_snippet.xml

# 4. Ensure the target artifact exists in Artifactory
# The environment setup puts the JAR on the Desktop. We must upload it to the repo 
# so the agent has something to find.
REPO_KEY="example-repo-local"
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
LOCAL_FILE="/home/ga/Desktop/commons-lang3-3.14.0.jar"

if [ -f "$LOCAL_FILE" ]; then
    echo "Deploying $LOCAL_FILE to $REPO_KEY..."
    curl -s -u admin:password -X PUT \
        "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_PATH}" \
        -T "$LOCAL_FILE" > /dev/null
    echo "Artifact deployed."
else
    echo "WARNING: Local artifact $LOCAL_FILE not found. Trying to download..."
    # Fallback if env setup failed to place file
    mkdir -p /tmp/dl
    wget -q -O /tmp/dl/commons-lang3.jar "https://repo1.maven.org/maven2/${ARTIFACT_PATH}"
    curl -s -u admin:password -X PUT \
        "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_PATH}" \
        -T "/tmp/dl/commons-lang3.jar" > /dev/null
    rm -rf /tmp/dl
fi

# Verify deployment
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${ARTIFACT_PATH}")
if [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: Failed to deploy artifact. HTTP $HTTP_CODE"
    exit 1
fi

# 5. Ensure Firefox is running and logged in
ensure_firefox_running "${ARTIFACTORY_URL}/ui/repos/tree/General/${REPO_KEY}"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="