#!/bin/bash
# export_result.sh - Verify the created volume and its contents
# Note: We use the VeraCrypt CLI to inspect the volume created by the agent via GUI

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# Configuration
VOLUME_PATH="/home/ga/Volumes/classified_volume.hc"
REPORT_PATH="/home/ga/Documents/volume_security_report.txt"
PASSWORD="Cl@ssified2024!"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VERIFY_MOUNT_POINT="/tmp/vc_verify_mount"

# Initialize Result Variables
VOLUME_EXISTS="false"
VOLUME_SIZE_BYTES=0
VOLUME_CREATED_AFTER_START="false"
AGENT_LEFT_MOUNTED="false"
MOUNT_SUCCESS="false"
ENCRYPTION_ALGO="unknown"
HASH_ALGO="unknown"
FILESYSTEM="unknown"
FILE1_MATCH="false"
FILE2_MATCH="false"
FILE3_MATCH="false"
REPORT_EXISTS="false"
REPORT_CONTENT_MATCH="false"

# 1. Check Volume Existence and Metadata
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    VOLUME_SIZE_BYTES=$(stat -c%s "$VOLUME_PATH" 2>/dev/null || echo "0")
    VOL_MTIME=$(stat -c%Y "$VOLUME_PATH" 2>/dev/null || echo "0")
    
    if [ "$VOL_MTIME" -gt "$TASK_START" ]; then
        VOLUME_CREATED_AFTER_START="true"
    fi
fi

# 2. Check if Agent Left Volume Mounted
# We check if the volume file is currently in the list of mounted volumes
if veracrypt --text --list 2>/dev/null | grep -q "$VOLUME_PATH"; then
    AGENT_LEFT_MOUNTED="true"
    echo "Agent left volume mounted. Dismounting for verification..."
    veracrypt --text --dismount "$VOLUME_PATH" --non-interactive 2>/dev/null || true
    sleep 1
fi

# 3. Mount Volume for Inspection
mkdir -p "$VERIFY_MOUNT_POINT"

if [ "$VOLUME_EXISTS" = "true" ]; then
    echo "Attempting to mount volume..."
    # Attempt mount with expected password
    if veracrypt --text --mount "$VOLUME_PATH" "$VERIFY_MOUNT_POINT" \
        --password="$PASSWORD" \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /tmp/mount_log.txt 2>&1; then
        
        MOUNT_SUCCESS="true"
        echo "Mount successful."

        # 3a. Check Volume Properties (Encryption/Hash)
        # Output format example: "Encryption Algorithm: AES"
        PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>/dev/null)
        
        # Extract algo using grep/sed. Note: "AES(Twofish(Serpent))" format varies by version
        ENCRYPTION_ALGO=$(echo "$PROPS" | grep -i "Encryption Algorithm" | cut -d: -f2 | xargs)
        HASH_ALGO=$(echo "$PROPS" | grep -i "Hash Algorithm" | cut -d: -f2 | xargs)
        
        # 3b. Check Filesystem
        # Use df -T on the mount point
        FILESYSTEM=$(df -T "$VERIFY_MOUNT_POINT" | tail -1 | awk '{print $2}')
        
        # 3c. Check File Integrity
        # We compare the checksum of files inside the volume with the stored original checksums
        
        # File 1: SF312_Nondisclosure_Agreement.txt
        if [ -f "$VERIFY_MOUNT_POINT/SF312_Nondisclosure_Agreement.txt" ]; then
            ACTUAL_SUM=$(sha256sum "$VERIFY_MOUNT_POINT/SF312_Nondisclosure_Agreement.txt" | awk '{print $1}')
            EXPECTED_SUM=$(cat /tmp/sum_file1.txt)
            if [ "$ACTUAL_SUM" == "$EXPECTED_SUM" ]; then
                FILE1_MATCH="true"
            fi
        fi
        
        # File 2: FY2024_Revenue_Budget.csv
        if [ -f "$VERIFY_MOUNT_POINT/FY2024_Revenue_Budget.csv" ]; then
            ACTUAL_SUM=$(sha256sum "$VERIFY_MOUNT_POINT/FY2024_Revenue_Budget.csv" | awk '{print $1}')
            EXPECTED_SUM=$(cat /tmp/sum_file2.txt)
            if [ "$ACTUAL_SUM" == "$EXPECTED_SUM" ]; then
                FILE2_MATCH="true"
            fi
        fi
        
        # File 3: backup_authorized_keys
        if [ -f "$VERIFY_MOUNT_POINT/backup_authorized_keys" ]; then
            ACTUAL_SUM=$(sha256sum "$VERIFY_MOUNT_POINT/backup_authorized_keys" | awk '{print $1}')
            EXPECTED_SUM=$(cat /tmp/sum_file3.txt)
            if [ "$ACTUAL_SUM" == "$EXPECTED_SUM" ]; then
                FILE3_MATCH="true"
            fi
        fi
        
        # Clean up: Dismount
        veracrypt --text --dismount "$VERIFY_MOUNT_POINT" --non-interactive 2>/dev/null || true
        
    else
        echo "Mount failed."
        cat /tmp/mount_log.txt
    fi
fi
rmdir "$VERIFY_MOUNT_POINT" 2>/dev/null || true

# 4. Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check if report contains key terms
    if grep -qi "AES" "$REPORT_PATH" && grep -qi "Whirlpool" "$REPORT_PATH"; then
        REPORT_CONTENT_MATCH="true"
    fi
fi

# 5. Capture Final Evidence
take_screenshot /tmp/task_final.png

# 6. Generate JSON Result
# Using python to safely generate JSON handles string escaping better than bash
python3 -c "
import json
import os

result = {
    'volume_exists': $VOLUME_EXISTS,
    'volume_size_bytes': $VOLUME_SIZE_BYTES,
    'volume_created_during_task': $VOLUME_CREATED_AFTER_START,
    'agent_left_mounted': $AGENT_LEFT_MOUNTED,
    'mount_success': $MOUNT_SUCCESS,
    'encryption_algo': '$ENCRYPTION_ALGO',
    'hash_algo': '$HASH_ALGO',
    'filesystem': '$FILESYSTEM',
    'file1_correct': $FILE1_MATCH,
    'file2_correct': $FILE2_MATCH,
    'file3_correct': $FILE3_MATCH,
    'report_exists': $REPORT_EXISTS,
    'report_content_correct': $REPORT_CONTENT_MATCH,
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="