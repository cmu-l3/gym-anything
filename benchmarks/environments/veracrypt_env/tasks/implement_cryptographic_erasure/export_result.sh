#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Cryptographic Erasure Result ==="

VOLUME_PATH="/home/ga/Volumes/investigation_data.hc"
SCRIPT_PATH="/home/ga/Documents/panic_wipe.sh"
MOUNT_POINT="/tmp/vc_verify_mount"

# 1. Verify File Existence and Size
FILE_EXISTS="false"
SIZE_MATCH="false"
CURRENT_SIZE=0

if [ -f "$VOLUME_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_SIZE=$(stat -c%s "$VOLUME_PATH")
    ORIGINAL_SIZE=$(cat /tmp/original_size.txt 2>/dev/null || echo "0")
    
    if [ "$CURRENT_SIZE" -eq "$ORIGINAL_SIZE" ]; then
        SIZE_MATCH="true"
    fi
fi

# 2. Verify Headers Modified
PRIMARY_WIPED="false"
BACKUP_WIPED="false"

if [ "$FILE_EXISTS" = "true" ]; then
    # Check Primary Header
    head -c 131072 "$VOLUME_PATH" > /tmp/current_primary_header.bin
    CURRENT_PRIMARY_HASH=$(sha256sum /tmp/current_primary_header.bin | cut -d' ' -f1)
    ORIGINAL_PRIMARY_HASH=$(cat /tmp/original_primary_hash.txt)
    
    if [ "$CURRENT_PRIMARY_HASH" != "$ORIGINAL_PRIMARY_HASH" ]; then
        PRIMARY_WIPED="true"
    fi

    # Check Backup Header
    tail -c 131072 "$VOLUME_PATH" > /tmp/current_backup_header.bin
    CURRENT_BACKUP_HASH=$(sha256sum /tmp/current_backup_header.bin | cut -d' ' -f1)
    ORIGINAL_BACKUP_HASH=$(cat /tmp/original_backup_hash.txt)
    
    if [ "$CURRENT_BACKUP_HASH" != "$ORIGINAL_BACKUP_HASH" ]; then
        BACKUP_WIPED="true"
    fi
    
    # Extra check: Are they just zeros? (Not strictly required by prompt "random data", 
    # but good to know for feedback).
    # We won't penalize for zeros, but high entropy is better.
fi

# 3. Functional Verification: Attempt to Mount
MOUNT_SUCCEEDED="false"
mkdir -p "$MOUNT_POINT"

# Try normal mount
if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
    --password='FreePress2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    MOUNT_SUCCEEDED="true"
    veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1 || true
fi
rmdir "$MOUNT_POINT" 2>/dev/null

# 4. Check Script Existence
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "volume_file_exists": $FILE_EXISTS,
    "volume_size_preserved": $SIZE_MATCH,
    "current_size": $CURRENT_SIZE,
    "primary_header_changed": $PRIMARY_WIPED,
    "backup_header_changed": $BACKUP_WIPED,
    "mount_succeeded": $MOUNT_SUCCEEDED,
    "script_exists": $SCRIPT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/erasure_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/erasure_result.json"
cat /tmp/erasure_result.json
echo "=== Export Complete ==="