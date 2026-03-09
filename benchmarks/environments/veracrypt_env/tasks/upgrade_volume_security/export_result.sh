#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Upgrade Volume Security Result ==="

VOLUME_PATH="/home/ga/Volumes/legacy_project.hc"
TEST_MOUNT="/tmp/vc_test_mount"
PASSWORD="UpgradeMe2024"

# Initialize result variables
VOLUME_EXISTS="false"
MOUNT_SUCCESS_DEFAULT_PIM="false"
MOUNT_SUCCESS_LEGACY_PIM="false"
DETECTED_PRF="unknown"
DATA_INTACT="false"

# 1. Check if volume exists
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
fi

mkdir -p "$TEST_MOUNT"

# 2. Attempt to mount with NEW settings (PIM 0 / Default)
echo "Attempting mount with Default PIM (Target State)..."
if veracrypt --text --mount "$VOLUME_PATH" "$TEST_MOUNT" \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    
    MOUNT_SUCCESS_DEFAULT_PIM="true"
    echo "Mount with default PIM succeeded."
    
    # Get Volume Properties to check PRF (Hash)
    PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>/dev/null)
    DETECTED_PRF=$(echo "$PROPS" | grep "Hash Algorithm:" | awk -F: '{print $2}' | xargs)
    echo "Detected PRF: $DETECTED_PRF"
    
    # Verify Data Integrity
    if md5sum -c /tmp/original_checksums.md5 --status --quiet 2>/dev/null; then
        DATA_INTACT="true"
        echo "Data integrity verified."
    else
        # Try checking existence if checksum fails (maybe metadata changed, though content shouldn't)
        if [ -f "$TEST_MOUNT/project_requirements.txt" ]; then
            DATA_INTACT="partial" # File exists but hash check failed or couldn't run
        fi
        echo "Data integrity check failed or partial."
    fi
    
    # Dismount
    veracrypt --text --dismount "$TEST_MOUNT" --non-interactive 2>/dev/null
    
else
    echo "Mount with default PIM failed."
    
    # 3. Fallback: Attempt to mount with OLD settings (PIM 485)
    # This helps distinguish between "volume corrupted" vs "task not attempted"
    echo "Attempting mount with Legacy PIM 485..."
    if veracrypt --text --mount "$VOLUME_PATH" "$TEST_MOUNT" \
        --password="$PASSWORD" \
        --pim=485 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive 2>/dev/null; then
        
        MOUNT_SUCCESS_LEGACY_PIM="true"
        PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>/dev/null)
        DETECTED_PRF=$(echo "$PROPS" | grep "Hash Algorithm:" | awk -F: '{print $2}' | xargs)
        
        veracrypt --text --dismount "$TEST_MOUNT" --non-interactive 2>/dev/null
    fi
fi

rmdir "$TEST_MOUNT" 2>/dev/null

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "mount_success_default_pim": $MOUNT_SUCCESS_DEFAULT_PIM,
    "mount_success_legacy_pim": $MOUNT_SUCCESS_LEGACY_PIM,
    "detected_prf": "$DETECTED_PRF",
    "data_intact": "$DATA_INTACT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="