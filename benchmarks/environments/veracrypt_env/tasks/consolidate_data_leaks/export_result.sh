#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Consolidate Data Leaks Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if volume is currently mounted (Agent should have dismounted it)
VOLUME_PATH="/home/ga/Volumes/legal_vault.hc"
IS_MOUNTED_BY_AGENT="false"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>/dev/null || echo "")
if echo "$MOUNT_LIST" | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED_BY_AGENT="true"
fi

# 3. Mount the volume to a temporary location to verify contents
echo "Mounting volume for verification..."
mkdir -p /tmp/verify_mount
MOUNT_SUCCESS="false"

# Try to mount with the known password
if veracrypt --text --mount "$VOLUME_PATH" /tmp/verify_mount \
    --password='Compliance2024!' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    MOUNT_SUCCESS="true"
    sleep 1
fi

# 4. Verify Contents of the Volume
SENSITIVE_FILES_IN_VOLUME=0
EXPECTED_HASH=$(cat /tmp/sensitive_hash.txt 2>/dev/null || echo "nohash")

if [ "$MOUNT_SUCCESS" = "true" ]; then
    # Find files in volume and check their content/hash
    # We look for files matching the hash or containing the string
    for f in $(find /tmp/verify_mount -type f); do
        if md5sum "$f" | grep -q "$EXPECTED_HASH"; then
            SENSITIVE_FILES_IN_VOLUME=$((SENSITIVE_FILES_IN_VOLUME + 1))
        elif grep -q "CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT" "$f"; then
            SENSITIVE_FILES_IN_VOLUME=$((SENSITIVE_FILES_IN_VOLUME + 1))
        fi
    done
    
    # Dismount verification mount
    veracrypt --text --dismount /tmp/verify_mount --non-interactive >/dev/null 2>&1 || true
fi
rmdir /tmp/verify_mount 2>/dev/null || true

# 5. Check if originals were removed (LEAK REMEDIATION)
LEAKS_REMAINING=0
for loc in "/home/ga/Desktop/draft_nda.txt" "/home/ga/Documents/SF312_Copy.txt" "/home/ga/Downloads/agreement_scan.txt"; do
    if [ -f "$loc" ]; then
        LEAKS_REMAINING=$((LEAKS_REMAINING + 1))
    fi
done

# 6. Check if distractors were preserved (PRECISION)
DISTRACTORS_MISSING=0
for loc in "/home/ga/Desktop/shopping_list.txt" "/home/ga/Documents/meeting_notes.txt"; do
    if [ ! -f "$loc" ]; then
        DISTRACTORS_MISSING=$((DISTRACTORS_MISSING + 1))
    fi
done

# 7. Generate JSON Result
RESULT_JSON=$(cat << EOF
{
    "is_mounted_by_agent": $IS_MOUNTED_BY_AGENT,
    "mount_verification_success": $MOUNT_SUCCESS,
    "sensitive_files_in_volume": $SENSITIVE_FILES_IN_VOLUME,
    "leaks_remaining_in_home": $LEAKS_REMAINING,
    "distractors_missing": $DISTRACTORS_MISSING,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="