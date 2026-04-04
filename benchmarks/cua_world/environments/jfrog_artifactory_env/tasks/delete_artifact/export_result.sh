#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting delete_artifact results ==="

REPO="example-repo-local"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Target Artifact (Should be 404)
LANG3_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar")

# 2. Check Target Folder (Should be 404 - clean deletion)
FOLDER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/org/apache/commons/commons-lang3/3.14.0")

# 3. Check Preserved Artifact (Should be 200)
IO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar")

# 4. Get Initial States (Anti-gaming)
INITIAL_LANG3=$(cat /tmp/initial_lang3_status.txt 2>/dev/null || echo "0")
INITIAL_IO=$(cat /tmp/initial_io_status.txt 2>/dev/null || echo "0")

# 5. Capture final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_lang3_status": $LANG3_STATUS,
    "final_folder_status": $FOLDER_STATUS,
    "final_io_status": $IO_STATUS,
    "initial_lang3_status": $INITIAL_LANG3,
    "initial_io_status": $INITIAL_IO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="