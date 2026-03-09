#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up delete_artifact task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory to be ready
wait_for_artifactory 120 || { echo "ERROR: Artifactory not ready"; exit 1; }

REPO="example-repo-local"
ARTIFACTS_DIR="/home/ga/artifacts"
LANG3_JAR="${ARTIFACTS_DIR}/commons-lang3/commons-lang3-3.14.0.jar"
IO_JAR="${ARTIFACTS_DIR}/commons-io/commons-io-2.15.1.jar"

# Verify source artifacts exist (from environment setup)
if [ ! -f "$LANG3_JAR" ] || [ ! -f "$IO_JAR" ]; then
    echo "ERROR: Source artifacts missing in /home/ga/artifacts"
    exit 1
fi

# Clean up any prior artifacts in the repo (idempotent setup)
echo "Cleaning up prior artifacts..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X DELETE \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-lang3/" > /dev/null 2>&1 || true
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X DELETE \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-io/" > /dev/null 2>&1 || true
sleep 2

# Deploy commons-lang3-3.14.0.jar (the one to be DELETED)
echo "Deploying commons-lang3-3.14.0.jar..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X PUT -T "$LANG3_JAR" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar" > /dev/null

# Deploy commons-io-2.15.1.jar (the one to be KEPT)
echo "Deploying commons-io-2.15.1.jar..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X PUT -T "$IO_JAR" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar" > /dev/null

sleep 3

# Verify both artifacts are deployed
echo "Verifying initial state..."
CHECK1=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar")
CHECK2=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar")

# Record initial artifact state
echo "$CHECK1" > /tmp/initial_lang3_status.txt
echo "$CHECK2" > /tmp/initial_io_status.txt

if [ "$CHECK1" != "200" ] || [ "$CHECK2" != "200" ]; then
    echo "WARNING: Deployment failed. Statuses: Lang3=$CHECK1, IO=$CHECK2"
fi

# Start Firefox and navigate to Artifacts browser
# We navigate to the tree view for the specific repo to save the agent some clicks
# but still require them to traverse the folder structure
TREE_URL="http://localhost:8082/ui/repos/tree/General/example-repo-local"
ensure_firefox_running "$TREE_URL"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== delete_artifact setup complete ==="