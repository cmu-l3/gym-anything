#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Enable Timestamp Updates Result ==="

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOLUME_PATH="/home/ga/Volumes/evidence_locker.hc"
CONFIG_PATH="/home/ga/.config/VeraCrypt/Configuration.xml"

# 1. Check Config Setting
# Look for <PreserveTimestamp>0</PreserveTimestamp>
CONFIG_CORRECT="false"
if [ -f "$CONFIG_PATH" ]; then
    if grep -q "<PreserveTimestamp>0</PreserveTimestamp>" "$CONFIG_PATH"; then
        CONFIG_CORRECT="true"
    fi
fi

# 2. Check Volume Timestamp
# It should be > TASK_START_TIME
VOLUME_UPDATED="false"
CURRENT_MTIME=$(stat -c %Y "$VOLUME_PATH" 2>/dev/null || echo "0")

if [ "$CURRENT_MTIME" -gt "$TASK_START_TIME" ]; then
    VOLUME_UPDATED="true"
fi

# 3. Verify File Content (Proof of Write)
# We need to mount the volume to check if the file is inside
FILE_COPIED="false"

# Create temp mount point
mkdir -p /tmp/vc_audit_check

# Try to mount (non-interactive)
echo "Verifying volume content..."
veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_audit_check \
    --password='Audit2024!' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null || true

if [ -f "/tmp/vc_audit_check/new_evidence.txt" ]; then
    FILE_COPIED="true"
fi

# Dismount and cleanup
veracrypt --text --dismount /tmp/vc_audit_check --non-interactive 2>/dev/null || true
rmdir /tmp/vc_audit_check 2>/dev/null || true

# 4. Check if volume is currently mounted (Task asks to dismount)
IS_MOUNTED="false"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1)
if echo "$MOUNT_LIST" | grep -q "evidence_locker"; then
    IS_MOUNTED="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Generate JSON
cat > /tmp/task_result.json << EOF
{
    "config_correct": $CONFIG_CORRECT,
    "volume_timestamp_updated": $VOLUME_UPDATED,
    "file_copied_to_volume": $FILE_COPIED,
    "volume_is_mounted": $IS_MOUNTED,
    "current_mtime": $CURRENT_MTIME,
    "task_start_time": $TASK_START_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json