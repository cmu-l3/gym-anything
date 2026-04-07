#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting setup_deniable_corporate_archive result ==="

# Configuration
VOLUME_PATH="/home/ga/Volumes/corporate_archive.hc"
OUTER_PASS="AuditReady2024!"
HIDDEN_PASS="InvestigationX!99"
KEYFILE_PATH="/home/ga/Keyfiles/investigation.key"
REPORT_PATH="/home/ga/Documents/archive_setup_report.txt"
OUTER_MOUNT="/tmp/verify_outer"
HIDDEN_MOUNT="/tmp/verify_hidden"
NOKEY_MOUNT="/tmp/verify_nokey"

# Get timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
TIMESTAMP_VALID="false"
IS_COPY="false"
KEYFILE_EXISTS="false"
KEYFILE_SIZE=0
OUTER_MOUNTABLE="false"
OUTER_ALGO="unknown"
OUTER_HASH="unknown"
OUTER_FILE_COUNT=0
OUTER_FILES_FOUND=""
OUTER_CHECKSUMS_MATCH="false"
HIDDEN_MOUNTABLE="false"
HIDDEN_ALGO="unknown"
HIDDEN_HASH="unknown"
HIDDEN_FILE_COUNT=0
HIDDEN_FILES_FOUND=""
HIDDEN_CHECKSUMS_MATCH="false"
PASSWORD_ONLY_BLOCKED="false"
FILESYSTEMS_DISTINCT="false"
OUTER_UUID=""
HIDDEN_UUID=""
REPORT_EXISTS="false"
REPORT_CONTENT_B64=""
ALL_DISMOUNTED="false"
AGENT_LEFT_MOUNTED="false"

# 1. Check Volume File Existence and Metadata
if [ -f "$VOLUME_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "$VOLUME_PATH" 2>/dev/null || echo "0")

    # Check creation timestamp
    FILE_MTIME=$(stat -c%Y "$VOLUME_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        TIMESTAMP_VALID="true"
    fi

    # Check if it's a copy of a pre-existing volume (anti-gaming)
    CURRENT_HASH=$(sha256sum "$VOLUME_PATH" | awk '{print $1}')
    if grep -q "$CURRENT_HASH" /tmp/pre_existing_volume_hashes.txt 2>/dev/null; then
        IS_COPY="true"
    fi
fi

# 2. Check Keyfile
if [ -f "$KEYFILE_PATH" ]; then
    KEYFILE_EXISTS="true"
    KEYFILE_SIZE=$(stat -c%s "$KEYFILE_PATH" 2>/dev/null || echo "0")
fi

# 3. Check if agent left volumes mounted
if veracrypt --text --list 2>/dev/null | grep -q "$VOLUME_PATH"; then
    AGENT_LEFT_MOUNTED="true"
fi

# Ensure everything is dismounted before our verification
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 2
mkdir -p "$OUTER_MOUNT" "$HIDDEN_MOUNT" "$NOKEY_MOUNT"

# 4. Verify Outer Volume (Decoy)
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Verifying Outer Volume..."
    if veracrypt --text --mount "$VOLUME_PATH" "$OUTER_MOUNT" \
        --password="$OUTER_PASS" --pim=0 --keyfiles="" \
        --protect-hidden=no --non-interactive >/dev/null 2>&1; then

        OUTER_MOUNTABLE="true"

        # Get encryption properties
        PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>/dev/null)
        OUTER_ALGO=$(echo "$PROPS" | grep -i "Encryption Algorithm" | cut -d: -f2 | xargs)
        # Note: VeraCrypt reports hash as "PKCS-5 PRF: HMAC-<algo>"
        OUTER_HASH=$(echo "$PROPS" | grep -i "PKCS-5 PRF" | cut -d: -f2 | xargs | sed 's/HMAC-//')

        # Count and list files
        OUTER_FILE_COUNT=$(ls "$OUTER_MOUNT" 2>/dev/null | wc -l)
        OUTER_FILES_FOUND=$(ls "$OUTER_MOUNT" 2>/dev/null | tr '\n' '|')

        # Verify checksums against ground truth
        OUTER_CHECKSUMS_MATCH="true"
        if [ -f /var/lib/veracrypt_task/decoy_checksums.txt ]; then
            while IFS=' ' read -r EXPECTED_SUM EXPECTED_FILE; do
                BASENAME=$(basename "$EXPECTED_FILE")
                if [ -f "$OUTER_MOUNT/$BASENAME" ]; then
                    ACTUAL_SUM=$(sha256sum "$OUTER_MOUNT/$BASENAME" | awk '{print $1}')
                    if [ "$ACTUAL_SUM" != "$EXPECTED_SUM" ]; then
                        OUTER_CHECKSUMS_MATCH="false"
                    fi
                else
                    OUTER_CHECKSUMS_MATCH="false"
                fi
            done < /var/lib/veracrypt_task/decoy_checksums.txt
        fi

        # Get UUID for distinctness check
        OUTER_UUID=$(blkid -o value -s UUID $(mount | grep "$OUTER_MOUNT" | awk '{print $1}') 2>/dev/null || echo "uuid_outer")

        veracrypt --text --dismount "$OUTER_MOUNT" --non-interactive 2>/dev/null || true
        sleep 1
    fi
fi

# 5. Verify Hidden Volume (with password + keyfile)
if [ "$FILE_EXISTS" = "true" ] && [ "$KEYFILE_EXISTS" = "true" ]; then
    echo "Verifying Hidden Volume..."
    if veracrypt --text --mount "$VOLUME_PATH" "$HIDDEN_MOUNT" \
        --password="$HIDDEN_PASS" --pim=0 --keyfiles="$KEYFILE_PATH" \
        --protect-hidden=no --non-interactive >/dev/null 2>&1; then

        HIDDEN_MOUNTABLE="true"

        # Get encryption properties
        PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>/dev/null)
        HIDDEN_ALGO=$(echo "$PROPS" | grep -i "Encryption Algorithm" | cut -d: -f2 | xargs)
        # Note: VeraCrypt reports hash as "PKCS-5 PRF: HMAC-<algo>"
        HIDDEN_HASH=$(echo "$PROPS" | grep -i "PKCS-5 PRF" | cut -d: -f2 | xargs | sed 's/HMAC-//')

        # Count and list files
        HIDDEN_FILE_COUNT=$(ls "$HIDDEN_MOUNT" 2>/dev/null | wc -l)
        HIDDEN_FILES_FOUND=$(ls "$HIDDEN_MOUNT" 2>/dev/null | tr '\n' '|')

        # Verify checksums against ground truth
        HIDDEN_CHECKSUMS_MATCH="true"
        if [ -f /var/lib/veracrypt_task/sensitive_checksums.txt ]; then
            while IFS=' ' read -r EXPECTED_SUM EXPECTED_FILE; do
                BASENAME=$(basename "$EXPECTED_FILE")
                if [ -f "$HIDDEN_MOUNT/$BASENAME" ]; then
                    ACTUAL_SUM=$(sha256sum "$HIDDEN_MOUNT/$BASENAME" | awk '{print $1}')
                    if [ "$ACTUAL_SUM" != "$EXPECTED_SUM" ]; then
                        HIDDEN_CHECKSUMS_MATCH="false"
                    fi
                else
                    HIDDEN_CHECKSUMS_MATCH="false"
                fi
            done < /var/lib/veracrypt_task/sensitive_checksums.txt
        fi

        # Get UUID for distinctness check
        HIDDEN_UUID=$(blkid -o value -s UUID $(mount | grep "$HIDDEN_MOUNT" | awk '{print $1}') 2>/dev/null || echo "uuid_hidden")

        veracrypt --text --dismount "$HIDDEN_MOUNT" --non-interactive 2>/dev/null || true
        sleep 1
    fi
fi

# 6. Check if password-only mount is blocked (keyfile truly required)
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Verifying password-only mount is blocked..."
    if ! veracrypt --text --mount "$VOLUME_PATH" "$NOKEY_MOUNT" \
        --password="$HIDDEN_PASS" --pim=0 --keyfiles="" \
        --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        PASSWORD_ONLY_BLOCKED="true"
    else
        # If it mounted, it means keyfile wasn't actually added - dismount
        veracrypt --text --dismount "$NOKEY_MOUNT" --non-interactive 2>/dev/null || true
    fi
fi

# 7. Check filesystem distinctness
if [ "$OUTER_MOUNTABLE" = "true" ] && [ "$HIDDEN_MOUNTABLE" = "true" ]; then
    if [ "$OUTER_UUID" != "$HIDDEN_UUID" ]; then
        FILESYSTEMS_DISTINCT="true"
    fi
fi

# 8. Check report file
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT_B64=$(base64 -w0 "$REPORT_PATH" 2>/dev/null || echo "")
fi

# 9. Check dismount state
MOUNTED_COUNT=$(veracrypt --text --list 2>/dev/null | grep -c "/dev/"); MOUNTED_COUNT=${MOUNTED_COUNT:-0}
if [ "$MOUNTED_COUNT" -eq 0 ] 2>/dev/null; then
    ALL_DISMOUNTED="true"
fi

# Clean up temp dirs
rmdir "$OUTER_MOUNT" "$HIDDEN_MOUNT" "$NOKEY_MOUNT" 2>/dev/null || true

# 10. Generate JSON Result (using heredoc to avoid bash/python boolean mismatch)
cat << JSONEOF > /tmp/task_result.json
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "timestamp_valid": $TIMESTAMP_VALID,
    "is_copy": $IS_COPY,
    "keyfile_exists": $KEYFILE_EXISTS,
    "keyfile_size": $KEYFILE_SIZE,
    "outer_mountable": $OUTER_MOUNTABLE,
    "outer_algo": "$OUTER_ALGO",
    "outer_hash": "$OUTER_HASH",
    "outer_file_count": $OUTER_FILE_COUNT,
    "outer_files_found": "$OUTER_FILES_FOUND",
    "outer_checksums_match": $OUTER_CHECKSUMS_MATCH,
    "hidden_mountable": $HIDDEN_MOUNTABLE,
    "hidden_algo": "$HIDDEN_ALGO",
    "hidden_hash": "$HIDDEN_HASH",
    "hidden_file_count": $HIDDEN_FILE_COUNT,
    "hidden_files_found": "$HIDDEN_FILES_FOUND",
    "hidden_checksums_match": $HIDDEN_CHECKSUMS_MATCH,
    "password_only_blocked": $PASSWORD_ONLY_BLOCKED,
    "filesystems_distinct": $FILESYSTEMS_DISTINCT,
    "outer_uuid": "$OUTER_UUID",
    "hidden_uuid": "$HIDDEN_UUID",
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT_B64",
    "agent_left_mounted": $AGENT_LEFT_MOUNTED,
    "all_dismounted": $ALL_DISMOUNTED,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
JSONEOF

chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
