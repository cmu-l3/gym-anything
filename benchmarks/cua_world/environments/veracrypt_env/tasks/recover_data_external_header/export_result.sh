#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting External Header Recovery Result ==="

VOL_PATH="/home/ga/Documents/project_alpha.hc"
RECOVERED_FILE="/home/ga/Documents/Recovered/Project_Alpha_Budget.csv"
LOST_PASS="LostPassword999"
TEMP_CHECK_MOUNT="/tmp/vc_integrity_check"

# 1. Check Data Recovery
FILE_RECOVERED="false"
FILE_INTEGRITY="false"
RECOVERED_HASH=""
TARGET_HASH=$(cat /tmp/target_file_hash.txt | awk '{print $1}')

if [ -f "$RECOVERED_FILE" ]; then
    FILE_RECOVERED="true"
    RECOVERED_HASH=$(md5sum "$RECOVERED_FILE" | awk '{print $1}')
    if [ "$RECOVERED_HASH" == "$TARGET_HASH" ]; then
        FILE_INTEGRITY="true"
    fi
fi

# 2. Check Volume State (Anti-Gaming / Method Check)
# We must verify the volume still has the "Lost" password.
# If the agent used "Restore Volume Header" instead of "Mount with external header",
# the volume password would have reverted to "BackupPass123".
VOLUME_INTACT="false"

mkdir -p "$TEMP_CHECK_MOUNT"

# Attempt mount with LOST password (should SUCCEED if volume is intact)
echo "Checking volume integrity with lost password..."
if veracrypt --text --mount "$VOL_PATH" "$TEMP_CHECK_MOUNT" \
    --password="$LOST_PASS" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive > /dev/null 2>&1; then
    
    VOLUME_INTACT="true"
    veracrypt --text --dismount "$TEMP_CHECK_MOUNT" --non-interactive > /dev/null 2>&1
else
    echo "Volume integrity check failed: Lost password no longer works."
fi

rmdir "$TEMP_CHECK_MOUNT" 2>/dev/null || true

# 3. Check if clean dismount occurred
# List all mounts
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
IS_CLEAN="false"
if ! echo "$MOUNT_LIST" | grep -q "$VOL_PATH"; then
    IS_CLEAN="true"
fi

# 4. Take Screenshot
take_screenshot /tmp/task_final.png

# 5. Export JSON
cat > /tmp/task_result.json << EOF
{
    "file_recovered": $FILE_RECOVERED,
    "file_integrity": $FILE_INTEGRITY,
    "volume_intact": $VOLUME_INTACT,
    "is_dismounted_clean": $IS_CLEAN,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json