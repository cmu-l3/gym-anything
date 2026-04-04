#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

EXTRACTED_FLAG_PATH="/home/ga/Evidence/extracted_flag.txt"
GROUND_TRUTH_PATH="/var/lib/veracrypt/ground_truth_flag.txt"
VOLUME_PATH="/home/ga/Evidence/sequestered_data.hc"
MOUNT_POINT="/home/ga/MountPoints/slot1"

# 1. Check if Extracted Flag Exists
FLAG_EXISTS="false"
EXTRACTED_CONTENT=""
if [ -f "$EXTRACTED_FLAG_PATH" ]; then
    FLAG_EXISTS="true"
    EXTRACTED_CONTENT=$(cat "$EXTRACTED_FLAG_PATH")
fi

# 2. Check if Volume is Mounted at Slot 1
VOLUME_MOUNTED="false"
MOUNT_CHECK=$(veracrypt --text --list --non-interactive 2>/dev/null || true)

# Simple check: Does list output contain our volume path and mount point?
if echo "$MOUNT_CHECK" | grep -q "$VOLUME_PATH" && echo "$MOUNT_CHECK" | grep -q "$MOUNT_POINT"; then
    VOLUME_MOUNTED="true"
fi

# Also check filesystem mount
FS_MOUNTED="false"
if mountpoint -q "$MOUNT_POINT"; then
    FS_MOUNTED="true"
fi

# 3. Get file timestamps to ensure it was created during task
FILE_CREATED_DURING_TASK="false"
if [ "$FLAG_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$EXTRACTED_FLAG_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Prepare Ground Truth for Verifier (copy to tmp for python script to read)
cp "$GROUND_TRUTH_PATH" /tmp/ground_truth_flag.txt
chmod 644 /tmp/ground_truth_flag.txt

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "flag_exists": $FLAG_EXISTS,
    "extracted_content": "$(echo "$EXTRACTED_CONTENT" | sed 's/"/\\"/g')",
    "volume_mounted_veracrypt": $VOLUME_MOUNTED,
    "volume_mounted_fs": $FS_MOUNTED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json