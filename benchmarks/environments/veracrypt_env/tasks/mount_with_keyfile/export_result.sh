#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting mount_with_keyfile result ==="

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific volume is mounted
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
IS_MOUNTED="false"
MOUNT_PATH=""

if echo "$MOUNT_LIST" | grep -q "secure_finance.hc"; then
    IS_MOUNTED="true"
    # Extract mount path from list output if possible
    # Output format typically: "1: /home/ga/Volumes/secure_finance.hc /home/ga/MountPoints/slot1 ..."
    MOUNT_PATH=$(echo "$MOUNT_LIST" | grep "secure_finance.hc" | awk '{print $3}')
fi

# 2. Check the intended mount point directly
TARGET_MOUNT_POINT="/home/ga/MountPoints/slot1"
MOUNT_POINT_ACTIVE="false"
FILES_ACCESSIBLE="false"
FOUND_FILES=""

if mountpoint -q "$TARGET_MOUNT_POINT"; then
    MOUNT_POINT_ACTIVE="true"
    
    # Check for expected files
    if [ -f "$TARGET_MOUNT_POINT/SF312_Nondisclosure_Agreement.txt" ] && \
       [ -f "$TARGET_MOUNT_POINT/FY2024_Revenue_Budget.csv" ]; then
        FILES_ACCESSIBLE="true"
        FOUND_FILES=$(ls "$TARGET_MOUNT_POINT" | tr '\n' ',')
    fi
fi

# 3. Check the output contents file
OUTPUT_FILE="/home/ga/Documents/volume_contents.txt"
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size)
    OUTPUT_CONTENT=$(head -n 20 "$OUTPUT_FILE")
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
# Safe string escaping
FOUND_FILES_SAFE=$(echo "$FOUND_FILES" | sed 's/"/\\"/g')
OUTPUT_CONTENT_SAFE=$(echo "$OUTPUT_CONTENT" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')

RESULT_JSON=$(cat << EOF
{
    "volume_is_mounted": $IS_MOUNTED,
    "mount_path_from_list": "$MOUNT_PATH",
    "target_mount_point_active": $MOUNT_POINT_ACTIVE,
    "files_accessible": $FILES_ACCESSIBLE,
    "found_files": "$FOUND_FILES_SAFE",
    "output_file_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_content": "$OUTPUT_CONTENT_SAFE",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="