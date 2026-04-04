#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting mount_readonly_inspect Result ==="

MOUNT_POINT="/home/ga/MountPoints/slot1"
INVENTORY_FILE="/home/ga/Documents/volume_inventory.txt"
VOLUME_PATH="/home/ga/Volumes/data_volume.hc"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Check 1: Volume Mounted ---
VOLUME_MOUNTED="false"
VOLUME_LISTED=$(veracrypt --text --list 2>/dev/null || true)
if echo "$VOLUME_LISTED" | grep -qi "data_volume.hc"; then
    VOLUME_MOUNTED="true"
fi

MOUNTPOINT_VALID="false"
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    MOUNTPOINT_VALID="true"
fi

# --- Check 2: Read-Only Status ---
IS_READ_ONLY="false"
MOUNT_OPTIONS=$(mount | grep "$MOUNT_POINT" 2>/dev/null || true)
if echo "$MOUNT_OPTIONS" | grep -q '\bro\b'; then
    IS_READ_ONLY="true"
else
    # Functional check: try to write
    if [ "$MOUNTPOINT_VALID" = "true" ]; then
        if touch "$MOUNT_POINT/.write_test_$$" 2>/dev/null; then
            IS_READ_ONLY="false"
            rm -f "$MOUNT_POINT/.write_test_$$" 2>/dev/null || true
        else
            # Touch failed, check if it was because of RO filesystem
            if touch "$MOUNT_POINT/.write_test_$$" 2>&1 | grep -qi "read-only"; then
                IS_READ_ONLY="true"
            fi
        fi
    fi
fi

# --- Check 3: Inventory File ---
INVENTORY_EXISTS="false"
INVENTORY_SIZE=0
INVENTORY_MTIME=0
INVENTORY_CONTENT=""

if [ -f "$INVENTORY_FILE" ]; then
    INVENTORY_EXISTS="true"
    INVENTORY_SIZE=$(stat -c%s "$INVENTORY_FILE" 2>/dev/null || echo "0")
    INVENTORY_MTIME=$(stat -c%Y "$INVENTORY_FILE" 2>/dev/null || echo "0")
    # Read content safely (first 2kb)
    INVENTORY_CONTENT=$(head -c 2048 "$INVENTORY_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# --- Check 4: Inventory Details ---
# Basic heuristic to check if it looks like `ls -l` output (contains dates/sizes)
HAS_DETAILS="false"
if [ "$INVENTORY_EXISTS" = "true" ]; then
    if grep -E '[0-9]{2,}' "$INVENTORY_FILE" >/dev/null 2>&1 || \
       grep -E '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)' "$INVENTORY_FILE" >/dev/null 2>&1; then
        HAS_DETAILS="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "volume_mounted": $VOLUME_MOUNTED,
    "mountpoint_valid": $MOUNTPOINT_VALID,
    "is_read_only": $IS_READ_ONLY,
    "inventory_exists": $INVENTORY_EXISTS,
    "inventory_size": $INVENTORY_SIZE,
    "inventory_mtime": $INVENTORY_MTIME,
    "inventory_content": "$INVENTORY_CONTENT",
    "has_details": $HAS_DETAILS,
    "task_start_time": $TASK_START,
    "mount_options": "$(echo "$MOUNT_OPTIONS" | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="