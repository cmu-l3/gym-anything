#!/bin/bash
echo "=== Exporting move_artifact_to_prod results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data from Artifactory API
REPO_SRC="dev-libs-local"
REPO_DEST="prod-libs-local"
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

# Check Source (Should be 404 if moved)
echo "Checking source repository..."
SRC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password \
    "http://localhost:8082/artifactory/api/storage/$REPO_SRC/$ARTIFACT_PATH")

# Check Destination (Should be 200)
echo "Checking destination repository..."
DEST_INFO=$(curl -s -u admin:password \
    "http://localhost:8082/artifactory/api/storage/$REPO_DEST/$ARTIFACT_PATH")

# Parse Destination Info (if exists)
DEST_EXISTS="false"
DEST_SHA256=""
DEST_SIZE="0"
DEST_CREATED=""

if echo "$DEST_INFO" | grep -q "\"uri\""; then
    DEST_EXISTS="true"
    # Extract details using python for reliability
    read -r DEST_SHA256 DEST_SIZE DEST_CREATED <<< $(echo "$DEST_INFO" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    sha = data.get('checksums', {}).get('sha256', '')
    size = data.get('size', 0)
    created = data.get('created', '')
    print(f'{sha} {size} {created}')
except:
    print(' 0 ')
")
fi

# Retrieve expected values stored during setup
EXPECTED_SHA256=$(cat /tmp/expected_sha256.txt 2>/dev/null || echo "")
EXPECTED_SIZE=$(cat /tmp/expected_size.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "source_status_code": "$SRC_STATUS",
    "dest_exists": $DEST_EXISTS,
    "dest_sha256": "$DEST_SHA256",
    "dest_size": $DEST_SIZE,
    "expected_sha256": "$EXPECTED_SHA256",
    "expected_size": $EXPECTED_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json