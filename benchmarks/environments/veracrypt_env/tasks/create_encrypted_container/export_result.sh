#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Encrypted Container Result ==="

# Check if the target volume file was created
VOLUME_PATH="/home/ga/Volumes/secret_archive.hc"
VOLUME_EXISTS="false"
VOLUME_SIZE_BYTES=0
VOLUME_SIZE_MB=0

if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    VOLUME_SIZE_BYTES=$(stat -c%s "$VOLUME_PATH" 2>/dev/null || echo "0")
    VOLUME_SIZE_MB=$((VOLUME_SIZE_BYTES / 1048576))
    echo "Volume found: $VOLUME_PATH ($VOLUME_SIZE_MB MB)"
fi

# Check current volume count vs initial
INITIAL_COUNT=$(cat /tmp/initial_volume_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 /home/ga/Volumes/*.hc 2>/dev/null | wc -l)

# Try to verify the volume is a valid VeraCrypt container by mounting it
VOLUME_VALID="false"
MOUNT_TEST_RESULT=""
ENCRYPTION_ALGO=""
HASH_ALGO=""

if [ "$VOLUME_EXISTS" = "true" ]; then
    # Attempt to mount with expected password to verify it's a valid container
    mkdir -p /tmp/vc_verify_mount
    MOUNT_OUTPUT=$(veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_verify_mount \
        --password='SecurePass2024' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive 2>&1) || true

    if mountpoint -q /tmp/vc_verify_mount 2>/dev/null; then
        VOLUME_VALID="true"
        MOUNT_TEST_RESULT="mount_success"

        # Get volume properties
        VC_INFO=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>&1) || true
        ENCRYPTION_ALGO=$(echo "$VC_INFO" | grep -i "Encryption Algorithm" | head -1 | sed 's/.*: *//' | tr -d '\n')
        HASH_ALGO=$(echo "$VC_INFO" | grep -i "Hash Algorithm" | head -1 | sed 's/.*: *//' | tr -d '\n')

        # List files inside the volume
        VOLUME_CONTENTS=$(ls -la /tmp/vc_verify_mount/ 2>/dev/null)

        # Dismount
        veracrypt --text --dismount /tmp/vc_verify_mount --non-interactive 2>/dev/null || true
        sleep 1
    else
        MOUNT_TEST_RESULT="mount_failed"
    fi
    rmdir /tmp/vc_verify_mount 2>/dev/null || true
fi

# Also check if any new .hc file was created (in case agent used different name)
NEW_VOLUMES=""
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    NEW_VOLUMES=$(ls -lt /home/ga/Volumes/*.hc 2>/dev/null | head -5)
fi

# Take final screenshot
take_screenshot /tmp/task_end.png

# Escape variables for JSON
ENCRYPTION_ALGO_SAFE=$(echo "$ENCRYPTION_ALGO" | sed 's/"/\\"/g')
HASH_ALGO_SAFE=$(echo "$HASH_ALGO" | sed 's/"/\\"/g')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_path": "$VOLUME_PATH",
    "volume_size_bytes": $VOLUME_SIZE_BYTES,
    "volume_size_mb": $VOLUME_SIZE_MB,
    "volume_valid": $VOLUME_VALID,
    "mount_test_result": "$MOUNT_TEST_RESULT",
    "encryption_algorithm": "$ENCRYPTION_ALGO_SAFE",
    "hash_algorithm": "$HASH_ALGO_SAFE",
    "initial_volume_count": $INITIAL_COUNT,
    "current_volume_count": $CURRENT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/veracrypt_create_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/veracrypt_create_result.json"
cat /tmp/veracrypt_create_result.json

echo "=== Export Complete ==="
