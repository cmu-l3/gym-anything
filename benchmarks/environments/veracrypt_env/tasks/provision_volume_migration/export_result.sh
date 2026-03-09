#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Provision Volume Migration Result ==="

TARGET_PATH="/home/ga/Volumes/Issued/jdoe_chimera.hc"
SOURCE_PATH="/home/ga/Volumes/onboarding_template.hc"

# 1. Check if target file exists
VOLUME_EXISTS="false"
VOLUME_SIZE_MB=0
if [ -f "$TARGET_PATH" ]; then
    VOLUME_EXISTS="true"
    SIZE_BYTES=$(stat -c%s "$TARGET_PATH")
    VOLUME_SIZE_MB=$((SIZE_BYTES / 1048576))
fi

# 2. Verify new volume properties (Algorithm & Password)
MOUNT_SUCCESS="false"
ALGORITHM_CORRECT="false"
DETECTED_ALGO="unknown"
FILES_COPIED="false"
FILES_MATCH="false"
MOUNT_POINT="/tmp/vc_verify_target"

if [ "$VOLUME_EXISTS" = "true" ]; then
    mkdir -p "$MOUNT_POINT"
    
    # Attempt mount with expected password
    echo "Attempting to mount target volume..."
    if veracrypt --text --mount "$TARGET_PATH" "$MOUNT_POINT" \
        --password='SerpentSecure2024!' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /dev/null 2>&1; then
        
        MOUNT_SUCCESS="true"
        
        # Check Encryption Algorithm
        VC_INFO=$(veracrypt --text --volume-properties "$TARGET_PATH" --non-interactive 2>/dev/null)
        DETECTED_ALGO=$(echo "$VC_INFO" | grep "Encryption Algorithm" | cut -d: -f2 | xargs)
        
        if [[ "$DETECTED_ALGO" == *"Serpent"* ]]; then
            ALGORITHM_CORRECT="true"
        fi
        
        # Check Files
        FILE_COUNT=$(ls -1 "$MOUNT_POINT" | wc -l)
        if [ "$FILE_COUNT" -ge 3 ]; then
            FILES_COPIED="true"
        fi
        
        # Verify File Integrity (Compare MD5s)
        # We need to strip paths to compare content hashes
        # Source hashes stored in /tmp/source_hashes.txt format: "hash  /path/to/file"
        # We generate current hashes and compare just the hash part
        
        CURRENT_HASHES=$(md5sum "$MOUNT_POINT"/* 2>/dev/null | awk '{print $1}' | sort)
        SOURCE_HASHES=$(cat /tmp/source_hashes.txt 2>/dev/null | awk '{print $1}' | sort)
        
        if [ "$CURRENT_HASHES" == "$SOURCE_HASHES" ] && [ -n "$CURRENT_HASHES" ]; then
            FILES_MATCH="true"
        fi
        
        # Dismount verification mount
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null
fi

# 3. Check for leftover mounts (Clean state)
LEFTOVER_MOUNTS=$(veracrypt --text --list --non-interactive 2>&1 | grep -c "^[0-9]" || echo "0")
CLEAN_STATE="false"
if [ "$LEFTOVER_MOUNTS" -eq 0 ]; then
    CLEAN_STATE="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Export JSON
cat > /tmp/provision_result.json << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_path": "$TARGET_PATH",
    "volume_size_mb": $VOLUME_SIZE_MB,
    "mount_success": $MOUNT_SUCCESS,
    "detected_algorithm": "$DETECTED_ALGO",
    "algorithm_correct": $ALGORITHM_CORRECT,
    "files_copied": $FILES_COPIED,
    "files_integrity_match": $FILES_MATCH,
    "clean_state": $CLEAN_STATE,
    "leftover_mount_count": $LEFTOVER_MOUNTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permission fix
chmod 666 /tmp/provision_result.json

echo "=== Export Complete ==="
cat /tmp/provision_result.json