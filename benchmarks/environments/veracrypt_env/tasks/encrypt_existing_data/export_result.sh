#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Encrypt Existing Data Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOLUME_PATH="/home/ga/Volumes/sensitive_encrypted.hc"
SOURCE_DIR="/home/ga/SensitiveData"
REPORT_FILE="transfer_report.txt"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Source Directory (Should be empty or deleted)
ORIGINALS_DELETED="false"
if [ ! -d "$SOURCE_DIR" ]; then
    ORIGINALS_DELETED="true"
    echo "Source directory removed."
else
    FILE_COUNT=$(ls -A "$SOURCE_DIR" 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -eq 0 ]; then
        ORIGINALS_DELETED="true"
        echo "Source directory is empty."
    else
        echo "Source directory still contains $FILE_COUNT files."
    fi
fi

# 3. Check Volume Existence and Metadata
VOLUME_EXISTS="false"
VOLUME_SIZE_MB=0
CREATED_AFTER_START="false"

if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    SIZE_BYTES=$(stat -c%s "$VOLUME_PATH")
    VOLUME_SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
    
    FILE_TIME=$(stat -c%Y "$VOLUME_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CREATED_AFTER_START="true"
    fi
fi

# 4. Verify Volume Content (Mounting Test)
MOUNT_SUCCESS="false"
FILES_FOUND=0
INTEGRITY_MATCH="false"
REPORT_FOUND="false"
REPORT_CONTENT_OK="false"
ENC_ALGO="unknown"
HASH_ALGO="unknown"

if [ "$VOLUME_EXISTS" = "true" ]; then
    echo "Attempting to mount volume for verification..."
    mkdir -p /tmp/vc_verify_mnt
    
    # Try to get volume info first
    PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>&1)
    ENC_ALGO=$(echo "$PROPS" | grep "Encryption Algorithm" | cut -d: -f2 | xargs)
    HASH_ALGO=$(echo "$PROPS" | grep "Hash Algorithm" | cut -d: -f2 | xargs)

    # Mount
    veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_verify_mnt \
        --password='SecureEncrypt2024!' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive 2>/dev/null
        
    if mountpoint -q /tmp/vc_verify_mnt; then
        MOUNT_SUCCESS="true"
        echo "Volume mounted successfully."
        
        # Check files
        EXPECTED_FILES=("SF312_Nondisclosure_Agreement.txt" "FY2024_Revenue_Budget.csv" "backup_authorized_keys" "data_manifest.sha256")
        for f in "${EXPECTED_FILES[@]}"; do
            if [ -f "/tmp/vc_verify_mnt/$f" ]; then
                FILES_FOUND=$((FILES_FOUND + 1))
            fi
        done
        
        # Verify Integrity
        if [ -f "/tmp/vc_verify_mnt/data_manifest.sha256" ]; then
            cd /tmp/vc_verify_mnt
            if sha256sum -c data_manifest.sha256 --status 2>/dev/null; then
                INTEGRITY_MATCH="true"
            fi
            cd - > /dev/null
        fi
        
        # Check Report
        if [ -f "/tmp/vc_verify_mnt/$REPORT_FILE" ]; then
            REPORT_FOUND="true"
            CONTENT=$(cat "/tmp/vc_verify_mnt/$REPORT_FILE")
            if echo "$CONTENT" | grep -q "FILES TRANSFERRED: 4" && echo "$CONTENT" | grep -q "INTEGRITY: VERIFIED"; then
                REPORT_CONTENT_OK="true"
            fi
        fi
        
        # Dismount
        veracrypt --text --dismount /tmp/vc_verify_mnt --non-interactive 2>/dev/null || true
    else
        echo "Failed to mount volume with provided password."
    fi
    rmdir /tmp/vc_verify_mnt 2>/dev/null || true
fi

# 5. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_size_mb": $VOLUME_SIZE_MB,
    "created_after_start": $CREATED_AFTER_START,
    "mount_success": $MOUNT_SUCCESS,
    "encryption_algorithm": "$ENC_ALGO",
    "hash_algorithm": "$HASH_ALGO",
    "files_found_count": $FILES_FOUND,
    "integrity_match": $INTEGRITY_MATCH,
    "report_found": $REPORT_FOUND,
    "report_content_ok": $REPORT_CONTENT_OK,
    "originals_deleted": $ORIGINALS_DELETED,
    "timestamp": $(date +%s)
}
EOF

# Secure file permissions for export
chmod 644 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="