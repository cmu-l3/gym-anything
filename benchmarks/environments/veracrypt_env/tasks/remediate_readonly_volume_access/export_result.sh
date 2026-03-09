#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Remediate Read-Only Access Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MOUNT_POINT="/home/ga/MountPoints/archive"
VOLUME_PATH="/home/ga/Volumes/department_archive.hc"
DIAGNOSIS_LOG="/home/ga/Documents/diagnosis.txt"
VALIDATION_FILE="$MOUNT_POINT/access_restored.txt"

# 1. Check Diagnosis Log
DIAGNOSIS_EXISTS="false"
DIAGNOSIS_CONTENT=""
if [ -f "$DIAGNOSIS_LOG" ]; then
    DIAGNOSIS_EXISTS="true"
    DIAGNOSIS_CONTENT=$(cat "$DIAGNOSIS_LOG" | head -n 5)
fi

# 2. Check Mount Status
IS_MOUNTED="false"
IS_READ_WRITE="false"
MOUNT_SOURCE=""

# Parse mount command
MOUNT_INFO=$(mount | grep "$MOUNT_POINT")

if [ -n "$MOUNT_INFO" ]; then
    IS_MOUNTED="true"
    
    # Check for 'rw' flag (mount output format: /dev/mapper/... on /path type vfat (rw,...))
    if echo "$MOUNT_INFO" | grep -q "(rw,"; then
        IS_READ_WRITE="true"
    fi
    
    # Check source (should be a veracrypt mapper device)
    MOUNT_SOURCE=$(echo "$MOUNT_INFO" | awk '{print $1}')
fi

# 3. Check Write Access Verification (File Creation)
VALIDATION_FILE_CREATED="false"
VALIDATION_CONTENT_MATCH="false"
SAMPLE_DATA_INTACT="false"

if [ "$IS_MOUNTED" = "true" ]; then
    # Check for the file agent was supposed to create
    if [ -f "$VALIDATION_FILE" ]; then
        VALIDATION_FILE_CREATED="true"
        CONTENT=$(cat "$VALIDATION_FILE")
        if [[ "$CONTENT" == *"Write access verified"* ]]; then
            VALIDATION_CONTENT_MATCH="true"
        fi
    fi
    
    # Check if original data survived
    if [ -f "$MOUNT_POINT/FY2024_Budget_v1.csv" ]; then
        SAMPLE_DATA_INTACT="true"
    fi
fi

# 4. Take Screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
# Escape strings for JSON
DIAGNOSIS_SAFE=$(echo "$DIAGNOSIS_CONTENT" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
MOUNT_INFO_SAFE=$(echo "$MOUNT_INFO" | sed 's/"/\\"/g')

RESULT_JSON=$(cat << EOF
{
    "task_start_time": $TASK_START,
    "diagnosis_exists": $DIAGNOSIS_EXISTS,
    "diagnosis_content": "$DIAGNOSIS_SAFE",
    "is_mounted": $IS_MOUNTED,
    "is_read_write": $IS_READ_WRITE,
    "mount_info": "$MOUNT_INFO_SAFE",
    "validation_file_exists": $VALIDATION_FILE_CREATED,
    "validation_content_correct": $VALIDATION_CONTENT_MATCH,
    "sample_data_intact": $SAMPLE_DATA_INTACT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="