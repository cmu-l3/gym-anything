#!/bin/bash
set -e
echo "=== Setting up find_artifact_checksum task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state (remove output file if exists from previous run)
rm -f /home/ga/artifact_checksum.txt

# 3. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# 4. Deploy artifacts to populate the repository
# We use the artifacts downloaded by the environment setup script
ARTIFACTS_DIR="/home/ga/artifacts"
REPO="example-repo-local"

echo "Deploying artifacts to $REPO..."

# Function to deploy a file
deploy_file() {
    local local_path="$1"
    local remote_path="$2"
    
    if [ -f "$local_path" ]; then
        echo "  Deploying $remote_path..."
        curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -T "$local_path" \
            "${ARTIFACTORY_URL}/artifactory/${REPO}/${remote_path}" > /dev/null
    else
        echo "  WARNING: Source file $local_path not found, skipping."
    fi
}

# Deploy Commons Lang 3 (The Target)
deploy_file \
    "$ARTIFACTS_DIR/commons-lang3/commons-lang3-3.14.0.jar" \
    "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

deploy_file \
    "$ARTIFACTS_DIR/commons-lang3/commons-lang3-3.14.0.pom" \
    "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom"

# Deploy Commons IO (Distractor)
deploy_file \
    "$ARTIFACTS_DIR/commons-io/commons-io-2.15.1.jar" \
    "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"

# 5. Verify deployment and record ground truth (hidden from agent)
TARGET_API_URL="${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

echo "Verifying deployment..."
sleep 2 # Give Artifactory a moment to index

RESPONSE=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "$TARGET_API_URL")
SHA256=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('checksums', {}).get('sha256', ''))" 2>/dev/null || echo "")

if [ -z "$SHA256" ] || [ "$SHA256" = "null" ]; then
    echo "ERROR: Failed to retrieve SHA-256 for deployed artifact. Deployment may have failed."
    echo "API Response: $RESPONSE"
    exit 1
fi

echo "$SHA256" > /tmp/ground_truth_sha256.txt
chmod 600 /tmp/ground_truth_sha256.txt # Restrict access
echo "Ground Truth SHA-256: $SHA256"

# 6. Prepare Firefox
# Start Firefox logged in, but at the home page (agent must navigate to artifacts)
echo "Starting Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/"

# Wait for window and maximize
wait_for_firefox 30
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="