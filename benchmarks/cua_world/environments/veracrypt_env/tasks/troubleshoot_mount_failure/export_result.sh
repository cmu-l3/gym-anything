#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Troubleshoot Mount Failure Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/troubleshoot_report.txt"
MOUNT_POINT="/home/ga/MountPoints/slot2"

# 1. Check Mount Status
VOLUME_MOUNTED="false"
MOUNT_CHECK_PASSED="false"
CORRECT_MOUNT_POINT="false"

# Check VeraCrypt list
VC_LIST=$(veracrypt --text --list 2>/dev/null || echo "")

if echo "$VC_LIST" | grep -q "project_vault.hc"; then
    VOLUME_MOUNTED="true"
    # Check if mounted to specific slot/path
    if echo "$VC_LIST" | grep -q "$MOUNT_POINT"; then
        CORRECT_MOUNT_POINT="true"
    fi
fi

# 2. Check File Accessibility (Evidence of successful decrypt)
FILES_ACCESSIBLE="false"
FILE_COUNT=0
FOUND_FILES=""

if [ "$VOLUME_MOUNTED" = "true" ] && mountpoint -q "$MOUNT_POINT"; then
    FILES_ACCESSIBLE="true"
    if [ -f "$MOUNT_POINT/SF312_Nondisclosure_Agreement.txt" ]; then
        FILE_COUNT=$((FILE_COUNT + 1))
    fi
    if [ -f "$MOUNT_POINT/FY2024_Revenue_Budget.csv" ]; then
        FILE_COUNT=$((FILE_COUNT + 1))
    fi
    if [ -f "$MOUNT_POINT/project_plan.txt" ]; then
        FILE_COUNT=$((FILE_COUNT + 1))
    fi
    FOUND_FILES=$(ls -1 "$MOUNT_POINT" 2>/dev/null | tr '\n' ',')
fi

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_TIMESTAMP_VALID="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 20) # Grab first 20 lines for verification
    
    # Check timestamp
    REPORT_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_TIME" -gt "$TASK_START" ]; then
        REPORT_TIMESTAMP_VALID="true"
    fi
fi

# 4. Anti-Gaming: Check if keyfile exists at original location (did they move it back?)
KEYFILE_AT_ORIGIN="false"
if [ -f "/home/ga/Keyfiles/project.key" ]; then
    KEYFILE_AT_ORIGIN="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "volume_mounted": $VOLUME_MOUNTED,
    "correct_mount_point": $CORRECT_MOUNT_POINT,
    "files_accessible": $FILES_ACCESSIBLE,
    "accessible_file_count": $FILE_COUNT,
    "found_files_list": "$FOUND_FILES",
    "report_exists": $REPORT_EXISTS,
    "report_timestamp_valid": $REPORT_TIMESTAMP_VALID,
    "keyfile_restored_to_origin": $KEYFILE_AT_ORIGIN,
    "report_content_preview": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permission safety
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="