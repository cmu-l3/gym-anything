#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Recover Lost Password Result ==="

# 1. Get Ground Truth
GROUND_TRUTH_ID=$(cat /var/lib/task_ground_truth_id.txt 2>/dev/null || echo "UNKNOWN")

# 2. Check Mount Status
VOLUME_PATH="/home/ga/Volumes/project_archive.hc"
EXPECTED_MOUNT_POINT="/home/ga/MountPoints/recovered"
IS_MOUNTED="false"
MOUNT_POINT_USED=""
MANIFEST_EXISTS="false"

# Check VeraCrypt list
VC_LIST=$(veracrypt --text --list --non-interactive 2>/dev/null || true)

if echo "$VC_LIST" | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED="true"
    # Extract mount point from list output
    # Format usually: Slot 1: ... /home/ga/Volumes/project_archive.hc /home/ga/MountPoints/recovered
    MOUNT_POINT_USED=$(echo "$VC_LIST" | grep "$VOLUME_PATH" | awk '{print $NF}')
fi

# Verify data accessibility
if [ -n "$MOUNT_POINT_USED" ] && [ -d "$MOUNT_POINT_USED" ]; then
    if [ -f "$MOUNT_POINT_USED/project_manifest.xml" ]; then
        MANIFEST_EXISTS="true"
    fi
fi

# 3. Check Recovered ID File
OUTPUT_FILE="/home/ga/Documents/recovered_id.txt"
FILE_EXISTS="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | tr -d ' \n\r\t')
fi

# 4. Anti-gaming: Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Screenshot
take_screenshot /tmp/task_final.png

# 6. JSON Export
RESULT_JSON=$(cat << EOF
{
    "is_volume_mounted": $IS_MOUNTED,
    "actual_mount_point": "$MOUNT_POINT_USED",
    "expected_mount_point": "$EXPECTED_MOUNT_POINT",
    "manifest_accessible": $MANIFEST_EXISTS,
    "output_file_exists": $FILE_EXISTS,
    "output_file_content": "$FILE_CONTENT",
    "ground_truth_id": "$GROUND_TRUTH_ID",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="