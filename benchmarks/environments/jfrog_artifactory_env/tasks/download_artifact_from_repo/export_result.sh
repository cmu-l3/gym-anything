#!/bin/bash
echo "=== Exporting download_artifact_from_repo results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target file details
DOWNLOAD_PATH="/home/ga/Downloads/commons-lang3-3.14.0.jar"
EXPECTED_SHA256=$(cat /tmp/expected_sha256.txt 2>/dev/null || echo "")

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_SHA256=""
FILE_CREATED_DURING_TASK="false"
DOWNLOAD_STATS_INCREMENTED="false"

if [ -f "$DOWNLOAD_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DOWNLOAD_PATH")
    FILE_MTIME=$(stat -c %Y "$DOWNLOAD_PATH")
    FILE_SHA256=$(sha256sum "$DOWNLOAD_PATH" | cut -d' ' -f1)
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Optional: Check Artifactory download statistics
# API: GET /api/storage/{repoKey}/{itemPath}?stats
# Note: Stats might not update instantly or might be disabled in OSS, treating as bonus signal
STATS_JSON=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/storage/example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar?stats")

DOWNLOAD_COUNT=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('downloadCount', 0))" 2>/dev/null || echo "0")

echo "Download count from Artifactory: $DOWNLOAD_COUNT"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$DOWNLOAD_PATH",
    "file_size": $FILE_SIZE,
    "file_sha256": "$FILE_SHA256",
    "expected_sha256": "$EXPECTED_SHA256",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "artifactory_download_count": $DOWNLOAD_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="