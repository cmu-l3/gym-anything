#!/bin/bash
# export_result.sh - Collect validation data
echo "=== Exporting mount_corrupted_header result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOLUME_PATH="/home/ga/Volumes/corrupted_volume.hc"
MOUNT_POINT="/home/ga/MountPoints/slot1"
REPORT_PATH="/home/ga/recovery_report.txt"

# 1. Check if volume is mounted at correct location
IS_MOUNTED="false"
MOUNT_SOURCE=""
if mountpoint -q "$MOUNT_POINT"; then
    IS_MOUNTED="true"
    # Try to verify source, though dm-crypt mappings obscure filenames often
    MOUNT_SOURCE=$(mount | grep "$MOUNT_POINT" | awk '{print $1}')
fi

# 2. Check accessibility of files
FILES_ACCESSIBLE="false"
FILE_COUNT=0
if [ "$IS_MOUNTED" = "true" ]; then
    if [ -f "$MOUNT_POINT/project_ssh_config" ] && \
       [ -f "$MOUNT_POINT/infrastructure_hosts" ] && \
       [ -f "$MOUNT_POINT/quarterly_metrics.csv" ]; then
        FILES_ACCESSIBLE="true"
        FILE_COUNT=$(ls -1 "$MOUNT_POINT" | wc -l)
    fi
fi

# 3. Calculate actual checksums of mounted files (if accessible)
ACTUAL_CHECKSUMS=""
if [ "$FILES_ACCESSIBLE" = "true" ]; then
    cd "$MOUNT_POINT"
    # Get checksums in a format easy to parse in python
    ACTUAL_CHECKSUMS=$(sha256sum project_ssh_config infrastructure_hosts quarterly_metrics.csv | awk '{print $1, $2}')
    cd /
fi

# 4. Check Recovery Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0) # Base64 encode to safely pass to JSON
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
fi

# 5. Anti-gaming: Check if primary header is still corrupted
# If agent restored the header (e.g. using backup tool) instead of mounting with backup flag,
# the first 512 bytes will no longer be zero.
HEADER_ZERO_COUNT=$(dd if="$VOLUME_PATH" bs=1 count=512 2>/dev/null | tr -d '\0' | wc -c)
IS_HEADER_CORRUPTED="false"
if [ "$HEADER_ZERO_COUNT" -eq 0 ]; then
    IS_HEADER_CORRUPTED="true" # It's all zeros, so corruption remains
fi

# 6. Read ground truth checksums
GROUND_TRUTH_CHECKSUMS=""
if [ -f /var/lib/veracrypt_task_data/expected_checksums.txt ]; then
    GROUND_TRUTH_CHECKSUMS=$(cat /var/lib/veracrypt_task_data/expected_checksums.txt | awk '{print $1, $2}')
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "is_mounted": $IS_MOUNTED,
    "mount_point": "$MOUNT_POINT",
    "files_accessible": $FILES_ACCESSIBLE,
    "mounted_file_count": $FILE_COUNT,
    "actual_checksums": "$ACTUAL_CHECKSUMS",
    "ground_truth_checksums": "$GROUND_TRUTH_CHECKSUMS",
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "report_mtime": $REPORT_MTIME,
    "is_header_still_corrupted": $IS_HEADER_CORRUPTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="