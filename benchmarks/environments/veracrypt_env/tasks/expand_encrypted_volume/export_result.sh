#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Expand Encrypted Volume Result ==="

VOLUME_PATH="/home/ga/Volumes/project_archive.hc"
REPORT_PATH="/home/ga/Documents/expansion_report.txt"
CHECKSUM_FILE="/var/lib/veracrypt_task/original_checksums.txt"
TEST_MOUNT="/tmp/vc_verify_expand"

# 1. Check Volume Existence and Size
VOLUME_EXISTS="false"
VOLUME_SIZE_MB=0
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    SIZE_BYTES=$(stat -c%s "$VOLUME_PATH")
    VOLUME_SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
fi

# 2. Verify Volume Mountability & Content
MOUNT_SUCCESS="false"
INTEGRITY_PASSED="false"
MARKER_FOUND="false"
FREE_SPACE_MB=0
FILES_FOUND=0

if [ "$VOLUME_EXISTS" = "true" ]; then
    mkdir -p "$TEST_MOUNT"
    
    # Attempt mount
    if veracrypt --text --mount "$VOLUME_PATH" "$TEST_MOUNT" \
        --password='ArchivePass2024' --pim=0 --keyfiles='' \
        --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        
        MOUNT_SUCCESS="true"
        
        # Check Integrity of original files
        if [ -f "$CHECKSUM_FILE" ]; then
            cd "$TEST_MOUNT"
            # sha256sum -c returns 0 if all files match
            if sha256sum --status -c "$CHECKSUM_FILE"; then
                INTEGRITY_PASSED="true"
            fi
            # Count how many original files are actually present
            FILES_FOUND=$(sha256sum -c "$CHECKSUM_FILE" 2>/dev/null | grep "OK" | wc -l)
            cd /
        fi
        
        # Check for Marker File
        if [ -f "$TEST_MOUNT/expansion_verified.txt" ]; then
            MARKER_CONTENT=$(cat "$TEST_MOUNT/expansion_verified.txt")
            if echo "$MARKER_CONTENT" | grep -qi "expansion successful"; then
                MARKER_FOUND="true"
            fi
        fi
        
        # Check Free Space (Available 1K-blocks / 1024 = MB)
        # df output: Filesystem 1K-blocks Used Available Use% Mounted on
        FREE_KB=$(df "$TEST_MOUNT" | tail -1 | awk '{print $4}')
        FREE_SPACE_MB=$((FREE_KB / 1024))
        
        # Dismount
        veracrypt --text --dismount "$TEST_MOUNT" --non-interactive >/dev/null 2>&1
    fi
    rmdir "$TEST_MOUNT" 2>/dev/null || true
fi

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT_VALID="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_TXT=$(cat "$REPORT_PATH")
    # Check for keywords "10", "50", and at least one filename
    if echo "$REPORT_TXT" | grep -q "50" && \
       (echo "$REPORT_TXT" | grep -q "Budget" || echo "$REPORT_TXT" | grep -q "Agreement"); then
        REPORT_CONTENT_VALID="true"
    fi
fi

# 4. Check if volume is currently dismounted (Anti-gaming)
# We check if the standard user mount points are active
IS_MOUNTED="false"
if mount | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED="true"
fi
# Also check VeraCrypt's list
if veracrypt --text --list --non-interactive 2>/dev/null | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "final_size_mb": $VOLUME_SIZE_MB,
    "mount_success": $MOUNT_SUCCESS,
    "integrity_passed": $INTEGRITY_PASSED,
    "original_files_found_count": $FILES_FOUND,
    "marker_file_valid": $MARKER_FOUND,
    "free_space_mb": $FREE_SPACE_MB,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_CONTENT_VALID,
    "is_currently_mounted": $IS_MOUNTED,
    "timestamp": "$(date +%s)"
}
EOF

# Set permissions for the copy function
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json