#!/bin/bash
# Setup for: audit_storage_run_gc task
echo "=== Setting up audit_storage_run_gc task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 2. Ensure example-repo-local exists (default in OSS, but verify)
# If not, create it
if ! repo_exists "example-repo-local"; then
    echo "Creating example-repo-local..."
    curl -u admin:password -X PUT \
        -H "Content-Type: application/json" \
        -d '{"key":"example-repo-local","rclass":"local","packageType":"maven"}' \
        "http://localhost:8082/artifactory/api/repositories/example-repo-local"
fi

# 3. Deploy artifacts to populate storage metrics
echo "Deploying artifacts..."
ARTIFACTS_DIR="/home/ga/artifacts"

# Deploy Commons Lang
if [ -f "$ARTIFACTS_DIR/commons-lang3/commons-lang3-3.14.0.jar" ]; then
    curl -u admin:password -X PUT \
        "http://localhost:8082/artifactory/example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar" \
        -T "$ARTIFACTS_DIR/commons-lang3/commons-lang3-3.14.0.jar"
fi

# Deploy Commons IO
if [ -f "$ARTIFACTS_DIR/commons-io/commons-io/commons-io-2.15.1.jar" ]; then
    curl -u admin:password -X PUT \
        "http://localhost:8082/artifactory/example-repo-local/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar" \
        -T "$ARTIFACTS_DIR/commons-io/commons-io/commons-io-2.15.1.jar"
fi

# 4. Create "garbage" (upload then delete)
# This ensures GC has something to do
echo "Creating garbage data..."
dd if=/dev/urandom of=/tmp/garbage.bin bs=1M count=5
curl -u admin:password -X PUT \
    "http://localhost:8082/artifactory/example-repo-local/garbage/temp.bin" \
    -T "/tmp/garbage.bin"
# Delete it (soft delete - binary stays until GC)
curl -u admin:password -X DELETE \
    "http://localhost:8082/artifactory/example-repo-local/garbage/temp.bin"
rm -f /tmp/garbage.bin

# 5. Trigger storage calculation so UI shows data
echo "Triggering storage calculation..."
curl -u admin:password -X POST "http://localhost:8082/artifactory/api/storageinfo/calculate"

# 6. Capture Ground Truth (Initial Storage Info)
echo "Capturing ground truth storage info..."
curl -s -u admin:password "http://localhost:8082/artifactory/api/storageinfo" > /tmp/initial_storage_info.json

# 7. Clean previous report
rm -f /home/ga/storage_audit_report.txt

# 8. Start Firefox on Home Page
ensure_firefox_running "http://localhost:8082/ui/"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="