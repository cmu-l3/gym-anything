#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Mount Volume Result ==="

# Check if any VeraCrypt volumes are currently mounted
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
echo "Current mounts: $MOUNT_LIST"

VOLUME_MOUNTED="false"
MOUNT_POINT=""
MOUNTED_FILES=""
MOUNTED_FILE_COUNT=0
DATA_VOLUME_MOUNTED="false"

# Check if data_volume.hc is mounted
if echo "$MOUNT_LIST" | grep -qi "data_volume"; then
    DATA_VOLUME_MOUNTED="true"
    VOLUME_MOUNTED="true"
fi

# Check all possible VeraCrypt mount points
for mp in /media/veracrypt1 /media/veracrypt2 /media/veracrypt3 \
          /tmp/vc_mount_tmp /home/ga/MountPoints/slot1 \
          /home/ga/MountPoints/slot2 /home/ga/MountPoints/slot3; do
    if mountpoint -q "$mp" 2>/dev/null; then
        VOLUME_MOUNTED="true"
        MOUNT_POINT="$mp"
        # List files in mounted volume
        MOUNTED_FILES=$(ls -1 "$mp" 2>/dev/null | tr '\n' ',')
        MOUNTED_FILE_COUNT=$(ls -1 "$mp" 2>/dev/null | wc -l)
        echo "Found mounted volume at $mp with $MOUNTED_FILE_COUNT files"
        break
    fi
done

# Also check by grepping mount output
if [ "$VOLUME_MOUNTED" = "false" ]; then
    VERACRYPT_MOUNTS=$(mount | grep veracrypt 2>/dev/null || echo "")
    if [ -n "$VERACRYPT_MOUNTS" ]; then
        VOLUME_MOUNTED="true"
        MOUNT_POINT=$(echo "$VERACRYPT_MOUNTS" | head -1 | awk '{print $3}')
        if [ -d "$MOUNT_POINT" ]; then
            MOUNTED_FILES=$(ls -1 "$MOUNT_POINT" 2>/dev/null | tr '\n' ',')
            MOUNTED_FILE_COUNT=$(ls -1 "$MOUNT_POINT" 2>/dev/null | wc -l)
        fi
    fi
fi

# Check for expected files
HAS_NDA="false"
HAS_BUDGET="false"
HAS_AUTH_KEYS="false"

if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    [ -f "$MOUNT_POINT/SF312_Nondisclosure_Agreement.txt" ] && HAS_NDA="true"
    [ -f "$MOUNT_POINT/FY2024_Revenue_Budget.csv" ] && HAS_BUDGET="true"
    [ -f "$MOUNT_POINT/backup_authorized_keys" ] && HAS_AUTH_KEYS="true"
fi

# Get initial state
INITIAL_MOUNTS=$(cat /tmp/initial_mount_state.txt 2>/dev/null || echo "none")

# Take screenshot
take_screenshot /tmp/task_end.png

# Escape for JSON
MOUNT_POINT_SAFE=$(echo "$MOUNT_POINT" | sed 's/"/\\"/g')
MOUNTED_FILES_SAFE=$(echo "$MOUNTED_FILES" | sed 's/"/\\"/g')

# Write result
RESULT_JSON=$(cat << EOF
{
    "volume_mounted": $VOLUME_MOUNTED,
    "data_volume_mounted": $DATA_VOLUME_MOUNTED,
    "mount_point": "$MOUNT_POINT_SAFE",
    "mounted_files": "$MOUNTED_FILES_SAFE",
    "mounted_file_count": $MOUNTED_FILE_COUNT,
    "has_sf312_nondisclosure_agreement": $HAS_NDA,
    "has_fy2024_revenue_budget": $HAS_BUDGET,
    "has_backup_authorized_keys": $HAS_AUTH_KEYS,
    "initial_mounts": "$(echo "$INITIAL_MOUNTS" | head -1 | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/veracrypt_mount_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/veracrypt_mount_result.json"
cat /tmp/veracrypt_mount_result.json

echo "=== Export Complete ==="
