#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Secure Data Migration Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOLUME_PATH="/home/ga/Volumes/secure_archive.hc"
SOURCE_DIR="/home/ga/Documents/SensitiveData"
REPORT_PATH="/home/ga/Documents/migration_report.txt"
HIDDEN_GT_DIR="/var/lib/veracrypt_task"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Volume Creation
VOLUME_EXISTS="false"
VOLUME_SIZE_BYTES=0
VOLUME_MTIME=0
CREATED_DURING_TASK="false"

if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    VOLUME_SIZE_BYTES=$(stat -c%s "$VOLUME_PATH")
    VOLUME_MTIME=$(stat -c%Y "$VOLUME_PATH")
    
    if [ "$VOLUME_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Verify Volume Properties and Content (Mount Check)
MOUNT_SUCCESS="false"
ENCRYPTION_ALGO=""
HASH_ALGO=""
FILES_PRESENT_COUNT=0
CHECKSUMS_MATCH_COUNT=0
FILES_MATCHING_LIST=""
MOUNT_TEMP="/tmp/vc_check_mount"

if [ "$VOLUME_EXISTS" = "true" ]; then
    echo "Attempting to mount volume for verification..."
    mkdir -p "$MOUNT_TEMP"
    
    # Try to mount with expected password
    if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_TEMP" \
        --password='SecureMigration2024!' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /tmp/mount_log.txt 2>&1; then
        
        MOUNT_SUCCESS="true"
        
        # Get properties
        PROPS=$(veracrypt --text --volume-properties "$VOLUME_PATH" --non-interactive 2>/dev/null)
        ENCRYPTION_ALGO=$(echo "$PROPS" | grep "Encryption Algorithm" | cut -d: -f2 | xargs)
        HASH_ALGO=$(echo "$PROPS" | grep "Hash Algorithm" | cut -d: -f2 | xargs)
        
        # Verify content
        echo "Verifying content in volume..."
        
        # We expect 5 specific files
        EXPECTED_FILES=(
            "SF312_Nondisclosure_Agreement.txt"
            "FY2024_Revenue_Budget.csv"
            "backup_authorized_keys"
            "employee_contacts.vcf"
            "incident_response_plan.md"
        )
        
        # Read ground truth checksums
        # format: hash  filename
        
        for fname in "${EXPECTED_FILES[@]}"; do
            if [ -f "$MOUNT_TEMP/$fname" ]; then
                FILES_PRESENT_COUNT=$((FILES_PRESENT_COUNT + 1))
                
                # Calculate actual hash
                ACTUAL_HASH=$(sha256sum "$MOUNT_TEMP/$fname" | awk '{print $1}')
                
                # Get expected hash from ground truth
                EXPECTED_HASH=$(grep "$fname" "$HIDDEN_GT_DIR/ground_truth_checksums.sha256" | awk '{print $1}')
                
                if [ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]; then
                    CHECKSUMS_MATCH_COUNT=$((CHECKSUMS_MATCH_COUNT + 1))
                    FILES_MATCHING_LIST="$FILES_MATCHING_LIST$fname,"
                else
                    echo "Mismatch for $fname: Expected $EXPECTED_HASH, got $ACTUAL_HASH"
                fi
            else
                echo "Missing file: $fname"
            fi
        done
        
        # Dismount
        veracrypt --text --dismount "$MOUNT_TEMP" --non-interactive 2>/dev/null || true
    else
        echo "Failed to mount volume with expected password."
        cat /tmp/mount_log.txt
    fi
    rmdir "$MOUNT_TEMP" 2>/dev/null || true
fi

# 4. Verify Migration Report
REPORT_EXISTS="false"
REPORT_HAS_PASS="false"
REPORT_HAS_CHECKSUMS="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
    
    if echo "$REPORT_CONTENT" | grep -qi "PASS"; then
        REPORT_HAS_PASS="true"
    fi
    
    # Check for presence of hex strings that look like sha256
    if grep -qE "[a-f0-9]{64}" "$REPORT_PATH"; then
        REPORT_HAS_CHECKSUMS="true"
    fi
fi

# 5. Verify Cleanup (Originals Removed)
ORIGINALS_REMOVED="false"
if [ ! -d "$SOURCE_DIR" ]; then
    ORIGINALS_REMOVED="true"
else
    # Check if directory is empty or just contains allowed leftovers
    # Task said "Securely delete original files... directory may remain empty or be removed"
    # Also "checksums.sha256 file should also be removed"
    
    FILE_COUNT=$(ls -A "$SOURCE_DIR" 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -eq 0 ]; then
        ORIGINALS_REMOVED="true"
    fi
fi

# 6. Check if any volumes are still mounted (Agent should have dismounted)
ANY_VOLUMES_MOUNTED="false"
if veracrypt --text --list --non-interactive | grep -q "^Slot"; then
    ANY_VOLUMES_MOUNTED="true"
fi

# Prepare JSON Result
cat > /tmp/task_result.json << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_created_during_task": $CREATED_DURING_TASK,
    "volume_size_bytes": $VOLUME_SIZE_BYTES,
    "mount_success": $MOUNT_SUCCESS,
    "encryption_algorithm": "$ENCRYPTION_ALGO",
    "hash_algorithm": "$HASH_ALGO",
    "files_present_count": $FILES_PRESENT_COUNT,
    "checksums_match_count": $CHECKSUMS_MATCH_COUNT,
    "matching_files": "${FILES_MATCHING_LIST%,}",
    "report_exists": $REPORT_EXISTS,
    "report_has_pass": $REPORT_HAS_PASS,
    "report_has_checksums": $REPORT_HAS_CHECKSUMS,
    "originals_removed": $ORIGINALS_REMOVED,
    "final_volumes_mounted": $ANY_VOLUMES_MOUNTED,
    "timestamp": $(date +%s)
}
EOF

# Secure copy to output
sudo cp /tmp/task_result.json /tmp/task_result_final.json
sudo chmod 666 /tmp/task_result_final.json

echo "Result JSON:"
cat /tmp/task_result_final.json
echo "=== Export Complete ==="