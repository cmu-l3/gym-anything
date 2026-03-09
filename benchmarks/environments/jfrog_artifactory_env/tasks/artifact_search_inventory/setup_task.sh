#!/bin/bash
set -e
echo "=== Setting up artifact_search_inventory task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Clean up previous report
rm -f /home/ga/artifact_inventory_report.txt

# Ensure Artifactory is ready
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# Define artifacts to deploy
ARTIFACTS_ROOT="/home/ga/artifacts"
REPO="example-repo-local"
BASE_URL="http://localhost:8082/artifactory"

# Ensure repo exists (it should by default in OSS, but safe to check)
if ! repo_exists "$REPO"; then
    echo "Creating $REPO..."
    # Fallback creation if missing (though typically auto-created)
    curl -u admin:password -X PUT -H "Content-Type: application/json" \
        -d '{"rclass":"local","packageType":"maven"}' \
        "${BASE_URL}/api/repositories/${REPO}"
fi

echo "Deploying artifacts..."

# Function to deploy file
deploy_artifact() {
    local local_path="$1"
    local repo_path="$2"
    
    if [ -f "$local_path" ]; then
        echo "Deploying $(basename "$local_path")..."
        curl -s -u admin:password -T "$local_path" "${BASE_URL}/${REPO}/${repo_path}" > /dev/null
    else
        echo "WARNING: Source file $local_path missing!"
    fi
}

# Deploy Commons Lang 3
deploy_artifact "$ARTIFACTS_ROOT/commons-lang3/commons-lang3-3.14.0.jar" "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
deploy_artifact "$ARTIFACTS_ROOT/commons-lang3/commons-lang3-3.14.0.pom" "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom"

# Deploy Commons IO
deploy_artifact "$ARTIFACTS_ROOT/commons-io/commons-io-2.15.1.jar" "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
deploy_artifact "$ARTIFACTS_ROOT/commons-io/commons-io-2.15.1.pom" "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.pom"

echo "Collecting ground truth metadata..."
# Query Artifactory API to get the EXACT size and SHA256 it has stored
# We save this to a hidden file for the export script to pick up
GROUND_TRUTH_FILE="/tmp/ground_truth_metadata.json"
echo "[" > "$GROUND_TRUTH_FILE"

get_metadata() {
    local path="$1"
    local comma="$2"
    
    # Get storage info
    local json
    json=$(curl -s -u admin:password "${BASE_URL}/api/storage/${REPO}/${path}")
    
    # Extract fields using python for reliability
    echo "$json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    out = {
        'path': '${REPO}/${path}',
        'size': d.get('size', 0),
        'sha256': d.get('checksums', {}).get('sha256', ''),
        'filename': '${path}'.split('/')[-1]
    }
    print(json.dumps(out) + '$comma')
except:
    pass
" >> "$GROUND_TRUTH_FILE"
}

get_metadata "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar" ","
get_metadata "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom" ","
get_metadata "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar" ","
get_metadata "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.pom" ""

echo "]" >> "$GROUND_TRUTH_FILE"
chmod 644 "$GROUND_TRUTH_FILE"

# Prepare UI
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="