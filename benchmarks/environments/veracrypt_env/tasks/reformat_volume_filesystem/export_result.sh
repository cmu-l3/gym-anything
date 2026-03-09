#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Reformat Volume Filesystem Result ==="

VOL_PATH="/home/ga/Volumes/data_volume.hc"
REPORT_PATH="/home/ga/Volumes/reformat_report.txt"
TRUTH_DIR="/var/lib/veracrypt_task"

# 1. Check if agent left volumes mounted (record state, then dismount for verification)
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
AGENT_LEFT_MOUNTED="false"
if echo "$MOUNT_LIST" | grep -q "$VOL_PATH"; then
    AGENT_LEFT_MOUNTED="true"
    veracrypt --text --dismount --non-interactive 2>/dev/null || true
    sleep 1
fi

# 2. Check 1: Filesystem Type (Must be ext4)
# Mount with --filesystem=none to inspect the raw device
FS_TYPE="unknown"
mkdir -p /tmp/vc_verify_fs
# Note: VeraCrypt maps the volume to a device mapper node
veracrypt --text --mount "$VOL_PATH" /tmp/vc_verify_fs \
    --password='MountMe2024' --pim=0 --keyfiles='' \
    --protect-hidden=no --filesystem=none --non-interactive 2>/dev/null || true

# Find the mapped device
MAPPER_DEV=$(veracrypt --text --list | grep "$VOL_PATH" | awk '{print $3}' | head -1)

if [ -n "$MAPPER_DEV" ]; then
    # Use blkid to get filesystem type of the inner volume
    FS_TYPE=$(blkid -o value -s TYPE "$MAPPER_DEV" 2>/dev/null || echo "unknown")
    veracrypt --text --dismount --non-interactive 2>/dev/null || true
fi
rmdir /tmp/vc_verify_fs 2>/dev/null || true

# 3. Check 2: Data Integrity
# Mount normally (should auto-detect ext4)
FILES_FOUND="false"
MD5_MATCH="false"
FILE_List=""

mkdir -p /tmp/vc_verify_data
if veracrypt --text --mount "$VOL_PATH" /tmp/vc_verify_data \
    --password='MountMe2024' --pim=0 --keyfiles='' \
    --protect-hidden=no --non-interactive 2>/dev/null; then
    
    VOLUME_MOUNTABLE="true"
    
    if mountpoint -q /tmp/vc_verify_data; then
        cd /tmp/vc_verify_data
        
        # Check files existence
        if [ -f "SF312_Nondisclosure_Agreement.txt" ] && \
           [ -f "FY2024_Revenue_Budget.csv" ] && \
           [ -f "backup_authorized_keys" ]; then
            FILES_FOUND="true"
            
            # Verify checksums
            md5sum * > /tmp/current_checksums.md5 2>/dev/null
            
            # Simple diff check (allowing for order differences)
            # We check if expected hashes are present in current hashes
            MISSING_HASHES=0
            while read -r line; do
                HASH=$(echo "$line" | awk '{print $1}')
                FILE=$(echo "$line" | awk '{print $2}')
                if ! grep -q "$HASH" /tmp/current_checksums.md5; then
                    MISSING_HASHES=$((MISSING_HASHES + 1))
                fi
            done < "$TRUTH_DIR/original_checksums.md5"
            
            if [ "$MISSING_HASHES" -eq 0 ]; then
                MD5_MATCH="true"
            fi
        fi
        
        FILE_LIST=$(ls -1 | tr '\n' ',')
        cd /
    fi
    veracrypt --text --dismount /tmp/vc_verify_data --non-interactive 2>/dev/null || true
else
    VOLUME_MOUNTABLE="false"
fi
rmdir /tmp/vc_verify_data 2>/dev/null || true

# 4. Check 3: Report File
REPORT_EXISTS="false"
REPORT_CONTENT_OK="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check if report contains "ext4" and filenames
    if grep -qi "ext4" "$REPORT_PATH" && \
       grep -q "SF312" "$REPORT_PATH"; then
        REPORT_CONTENT_OK="true"
    fi
fi

# 5. Final Screenshot
take_screenshot /tmp/task_final.png

# 6. JSON Export
# Use Python for safe JSON generation
python3 -c "
import json
import os

result = {
    'volume_mountable': '$VOLUME_MOUNTABLE' == 'true',
    'filesystem_type': '$FS_TYPE',
    'files_preserved': '$FILES_FOUND' == 'true',
    'checksums_match': '$MD5_MATCH' == 'true',
    'agent_left_mounted': '$AGENT_LEFT_MOUNTED' == 'true',
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_content_valid': '$REPORT_CONTENT_OK' == 'true',
    'file_list': '$FILE_LIST',
    'task_timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported:"
cat /tmp/task_result.json