#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Volume Integrity Result ==="

REPORT_PATH="/home/ga/Volumes/integrity_report.txt"
MANIFEST_PATH="/home/ga/Volumes/integrity_manifest.sha256"
MOUNT_POINT="/home/ga/MountPoints/slot1"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp against task start
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy report to temp for verifier to read
    cp "$REPORT_PATH" /tmp/integrity_report_export.txt
    chmod 666 /tmp/integrity_report_export.txt
fi

# 2. Check Volume Mount State (should be dismounted)
VOLUME_DISMOUNTED="true"
MOUNT_CHECK=$(veracrypt --text --list 2>/dev/null || echo "")

if echo "$MOUNT_CHECK" | grep -qi "slot1\|data_volume\|MountPoints"; then
    VOLUME_DISMOUNTED="false"
fi
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    VOLUME_DISMOUNTED="false"
fi

# 3. Get Expected Files (Ground Truth)
# We copy the ground truth manifest to tmp for the verifier to read
if [ -f "/var/lib/veracrypt_ground_truth/integrity_manifest.sha256" ]; then
    cp "/var/lib/veracrypt_ground_truth/integrity_manifest.sha256" /tmp/ground_truth_manifest.txt
    chmod 666 /tmp/ground_truth_manifest.txt
fi

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "volume_dismounted": $VOLUME_DISMOUNTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="