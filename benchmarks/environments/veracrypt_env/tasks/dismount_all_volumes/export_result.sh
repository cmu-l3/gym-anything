#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Dismount All Volumes Result ==="

# Check current mount state
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
echo "Current mounts after task: $MOUNT_LIST"

CURRENT_MOUNTED=0
if echo "$MOUNT_LIST" | grep -q "^[0-9]"; then
    CURRENT_MOUNTED=$(echo "$MOUNT_LIST" | grep -c "^[0-9]" 2>/dev/null || echo "0")
fi

# Also check via mount command
VERACRYPT_MOUNTS=$(mount | grep veracrypt 2>/dev/null | wc -l)

# Check if any veracrypt mount points are still active
ACTIVE_MOUNT_POINTS=0
for mp in /media/veracrypt1 /media/veracrypt2 /media/veracrypt3 \
          /media/veracrypt4 /media/veracrypt5; do
    if mountpoint -q "$mp" 2>/dev/null; then
        ACTIVE_MOUNT_POINTS=$((ACTIVE_MOUNT_POINTS + 1))
    fi
done

# Get initial state
INITIAL_MOUNTED=$(cat /tmp/initial_mounted_count.txt 2>/dev/null || echo "0")

# Determine if all were dismounted
ALL_DISMOUNTED="false"
if [ "$CURRENT_MOUNTED" -eq 0 ] && [ "$ACTIVE_MOUNT_POINTS" -eq 0 ] && [ "$VERACRYPT_MOUNTS" -eq 0 ]; then
    ALL_DISMOUNTED="true"
fi

# Check if count decreased
COUNT_DECREASED="false"
if [ "$CURRENT_MOUNTED" -lt "$INITIAL_MOUNTED" ] || [ "$ACTIVE_MOUNT_POINTS" -eq 0 ]; then
    COUNT_DECREASED="true"
fi

# Take screenshot
take_screenshot /tmp/task_end.png

# Write result
RESULT_JSON=$(cat << EOF
{
    "initial_mounted_count": $INITIAL_MOUNTED,
    "current_mounted_count": $CURRENT_MOUNTED,
    "veracrypt_mount_count": $VERACRYPT_MOUNTS,
    "active_mount_points": $ACTIVE_MOUNT_POINTS,
    "all_dismounted": $ALL_DISMOUNTED,
    "count_decreased": $COUNT_DECREASED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/veracrypt_dismount_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/veracrypt_dismount_result.json"
cat /tmp/veracrypt_dismount_result.json

echo "=== Export Complete ==="
