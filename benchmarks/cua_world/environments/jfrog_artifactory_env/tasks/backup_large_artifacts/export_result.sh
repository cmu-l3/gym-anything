#!/bin/bash
echo "=== Exporting backup_large_artifacts results ==="

source /workspace/scripts/task_utils.sh

BACKUP_DIR="/home/ga/large_files_backup"
MANIFEST_FILE="$BACKUP_DIR/manifest.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Directory Existence
if [ -d "$BACKUP_DIR" ]; then
    DIR_EXISTS="true"
else
    DIR_EXISTS="false"
fi

# 2. Analyze files in backup directory
FILES_JSON="[]"
MANIFEST_CONTENT=""
MANIFEST_EXISTS="false"

if [ "$DIR_EXISTS" = "true" ]; then
    # Generate a JSON array of file details
    FILES_JSON=$(find "$BACKUP_DIR" -maxdepth 1 -type f -not -name "manifest.txt" -printf '{"name":"%f","size":%s,"sha256":"' -exec sha256sum {} \; | awk '{print $1"\"}, "}' | sed '$s/, $//')
    FILES_JSON="[$FILES_JSON]"
    
    # Check manifest
    if [ -f "$MANIFEST_FILE" ]; then
        MANIFEST_EXISTS="true"
        MANIFEST_CONTENT=$(cat "$MANIFEST_FILE" | base64 -w 0)
    fi
fi

# 3. Check for ground truth checksums (from setup)
GROUND_TRUTH_CHECKSUMS=""
if [ -f /tmp/ground_truth_checksums.txt ]; then
    GROUND_TRUTH_CHECKSUMS=$(cat /tmp/ground_truth_checksums.txt | base64 -w 0)
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "dir_exists": $DIR_EXISTS,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_content_base64": "$MANIFEST_CONTENT",
    "ground_truth_checksums_base64": "$GROUND_TRUTH_CHECKSUMS",
    "files": $FILES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="