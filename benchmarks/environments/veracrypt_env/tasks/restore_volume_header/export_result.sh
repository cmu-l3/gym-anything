#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Restore Volume Header Result ==="

VOL_PATH="/home/ga/Volumes/critical_data.hc"
MOUNT_POINT="/home/ga/MountPoints/slot1"
REPORT_PATH="/home/ga/Documents/recovery_report.txt"
PASSWORD="DR-Restore#2024!"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if volume is mounted
IS_MOUNTED="false"
MOUNTED_AT=""
if mount | grep -q "$MOUNT_POINT"; then
    IS_MOUNTED="true"
    MOUNTED_AT="$MOUNT_POINT"
else
    # Check if mounted elsewhere
    MOUNTED_AT=$(mount | grep "veracrypt" | grep "$VOL_PATH" | awk '{print $3}' | head -1)
    if [ -n "$MOUNTED_AT" ]; then
        IS_MOUNTED="true"
    fi
fi

# 2. Check content of mounted volume
FILES_FOUND="[]"
HAS_RECOVERY_FILE="false"
RECOVERY_CODE_IN_VOL=""
FILES_MATCH_EXPECTED="false"

if [ "$IS_MOUNTED" = "true" ]; then
    # List files
    FILES=$(ls -1 "$MOUNTED_AT")
    # Convert to JSON array
    FILES_FOUND=$(echo "$FILES" | jq -R . | jq -s .)
    
    # Check specific file
    if [ -f "$MOUNTED_AT/RECOVERY_VERIFICATION.txt" ]; then
        HAS_RECOVERY_FILE="true"
        RECOVERY_CODE_IN_VOL=$(cat "$MOUNTED_AT/RECOVERY_VERIFICATION.txt")
    fi

    # Check for other expected files
    if [ -f "$MOUNTED_AT/SF312_Nondisclosure_Agreement.txt" ] && \
       [ -f "$MOUNTED_AT/FY2024_Revenue_Budget.csv" ]; then
        FILES_MATCH_EXPECTED="true"
    fi
fi

# 3. Check report file
REPORT_EXISTS="false"
REPORT_CODE_MATCH="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    # Check first line for code
    FIRST_LINE=$(head -n 1 "$REPORT_PATH" | tr -d '[:space:]')
    EXPECTED_CODE="VERIFIED-DR-7F3A9B2E-OK"
    if [ "$FIRST_LINE" == "$EXPECTED_CODE" ]; then
        REPORT_CODE_MATCH="true"
    fi
fi

# 4. Check if volume header was actually restored (by trying to mount if not mounted)
HEADER_RESTORED="false"
if [ "$IS_MOUNTED" = "true" ]; then
    HEADER_RESTORED="true"
else
    # Try to mount temporarily to check header health
    mkdir -p /tmp/check_header
    if veracrypt --text --mount "$VOL_PATH" /tmp/check_header --password="$PASSWORD" --pim=0 --keyfiles="" --non-interactive 2>/dev/null; then
        HEADER_RESTORED="true"
        veracrypt --text --dismount /tmp/check_header --non-interactive 2>/dev/null || true
    fi
    rmdir /tmp/check_header 2>/dev/null || true
fi

# 5. Anti-gaming: Check if report was created during task
REPORT_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
if [ "$REPORT_EXISTS" = "true" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "volume_mounted": $IS_MOUNTED,
    "mount_point": "$MOUNTED_AT",
    "header_restored": $HEADER_RESTORED,
    "files_match_expected": $FILES_MATCH_EXPECTED,
    "has_recovery_file": $HAS_RECOVERY_FILE,
    "report_exists": $REPORT_EXISTS,
    "report_code_match": $REPORT_CODE_MATCH,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
echo "Result saved."
cat /tmp/task_result.json