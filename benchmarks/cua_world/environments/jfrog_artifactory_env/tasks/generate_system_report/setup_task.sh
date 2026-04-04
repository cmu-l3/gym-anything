#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up generate_system_report task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory to be ready
wait_for_artifactory 120

# 1. Deploy artifacts to generate non-zero storage usage
# We use curl to deploy the pre-downloaded artifacts from the environment
echo "Deploying artifacts to populate storage metrics..."

ARTIFACT_JAR="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
if [ -f "$ARTIFACT_JAR" ]; then
    # Deploy to example-repo-local
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X PUT \
        -T "$ARTIFACT_JAR" \
        "${ARTIFACTORY_URL}/artifactory/example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar" \
        > /dev/null 2>&1
    echo "Deployed commons-lang3 JAR"
else
    echo "WARNING: Artifact $ARTIFACT_JAR not found, skipping deployment"
fi

# Deploy a second artifact to ensure count/size changes
COMMONS_IO_JAR="/home/ga/artifacts/commons-io/commons-io-2.15.1.jar"
if [ -f "$COMMONS_IO_JAR" ]; then
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X PUT \
        -T "$COMMONS_IO_JAR" \
        "${ARTIFACTORY_URL}/artifactory/example-repo-local/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar" \
        > /dev/null 2>&1
    echo "Deployed commons-io JAR"
fi

# Allow storage calculation to update (Artifactory storage calc can be async or on-demand)
# We trigger the storage summary API to ensure it's calculated
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${ARTIFACTORY_URL}/artifactory/api/storageinfo/calculate" > /dev/null 2>&1 || true
sleep 2

# 2. Capture Ground Truth Data (Hidden from agent, used for verification)
echo "Capturing ground truth data..."

# Version
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/version" \
    > /tmp/ground_truth_version.json

# Repository List
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/repositories" \
    > /tmp/ground_truth_repos.json

# Storage Info
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/storageinfo" \
    > /tmp/ground_truth_storage.json

# Verify we got valid JSON
if ! jq . /tmp/ground_truth_version.json >/dev/null 2>&1; then
    echo "ERROR: Failed to capture Artifactory version"
    exit 1
fi

# 3. Clean up previous run artifacts
rm -f /home/ga/system_report.txt

# 4. Prepare UI
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 5
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="