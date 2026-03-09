#!/bin/bash
# Note: Use bash explicitly, no set -e to handle mounting failures gracefully
echo "=== Exporting nested encryption workflow result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Initialize Result Variables ---
VOLUMES_DISMOUNTED="false"
INNER_FOUND="false"
INNER_SIZE=0
INNER_MOUNT_SUCCESS="false"
INNER_ALGO=""
FILES_FOUND=0
FILE_INTEGRITY_OK="false"
OUTER_MODIFIED_TIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Step 1: Check if volumes are currently mounted (Should be none) ---
MOUNTED_COUNT=$(veracrypt --text -l 2>/dev/null | grep -c "Slot" || echo "0")
if [ "$MOUNTED_COUNT" -eq "0" ]; then
    VOLUMES_DISMOUNTED="true"
else
    # If volumes are mounted, force dismount for verification
    echo "Volumes still mounted. Force dismounting for verification..."
    veracrypt --text --dismount --non-interactive 2>/dev/null || true
    sleep 2
fi

# --- Step 2: Mount outer volume to inspect contents ---
mkdir -p /tmp/vc_verify_outer
echo "Mounting outer volume for inspection..."
if veracrypt --text --mount /home/ga/Volumes/outer_vault.hc /tmp/vc_verify_outer \
    --password='OuterVault2024!' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive >/dev/null 2>&1; then
    
    # Check for inner volume file
    if [ -f /tmp/vc_verify_outer/inner_vault.hc ]; then
        INNER_FOUND="true"
        INNER_SIZE=$(stat -c%s /tmp/vc_verify_outer/inner_vault.hc 2>/dev/null || echo "0")
        
        # --- Step 3: Mount inner volume to inspect contents ---
        mkdir -p /tmp/vc_verify_inner
        echo "Mounting inner volume for inspection..."
        if veracrypt --text --mount /tmp/vc_verify_outer/inner_vault.hc /tmp/vc_verify_inner \
            --password='InnerSecret!99' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive >/dev/null 2>&1; then
            
            INNER_MOUNT_SUCCESS="true"
            
            # Check Encryption Algorithm
            VC_INFO=$(veracrypt --text --volume-properties /tmp/vc_verify_inner 2>/dev/null || echo "")
            INNER_ALGO=$(echo "$VC_INFO" | grep -i "Encryption Algorithm" | cut -d: -f2 | xargs)
            if [ -z "$INNER_ALGO" ]; then
                 # Fallback if volume-properties fails on mount point
                 VC_INFO=$(veracrypt --text -l -v | grep -A 20 "inner_vault.hc")
                 INNER_ALGO=$(echo "$VC_INFO" | grep -i "Encryption Algorithm" | cut -d: -f2 | xargs)
            fi

            # Check Files
            if [ -f /tmp/vc_verify_inner/SF312_Nondisclosure_Agreement.txt ]; then
                FILES_FOUND=$((FILES_FOUND + 1))
            fi
            if [ -f /tmp/vc_verify_inner/FY2024_Revenue_Budget.csv ]; then
                FILES_FOUND=$((FILES_FOUND + 1))
            fi
            
            # Check Integrity
            if [ "$FILES_FOUND" -eq "2" ]; then
                MD5_1=$(md5sum /tmp/vc_verify_inner/SF312_Nondisclosure_Agreement.txt | awk '{print $1}')
                MD5_2=$(md5sum /tmp/vc_verify_inner/FY2024_Revenue_Budget.csv | awk '{print $1}')
                
                EXPECTED_MD5_1=$(grep "SF312" /tmp/expected_checksums.txt | awk '{print $1}')
                EXPECTED_MD5_2=$(grep "Revenue" /tmp/expected_checksums.txt | awk '{print $1}')
                
                if [ "$MD5_1" == "$EXPECTED_MD5_1" ] && [ "$MD5_2" == "$EXPECTED_MD5_2" ]; then
                    FILE_INTEGRITY_OK="true"
                fi
            fi
            
            # Dismount inner
            veracrypt --text --dismount /tmp/vc_verify_inner --non-interactive 2>/dev/null || true
        else
            echo "Failed to mount inner volume."
        fi
        rmdir /tmp/vc_verify_inner 2>/dev/null || true
    else
        echo "Inner volume file not found in outer volume."
    fi
    
    # Dismount outer
    veracrypt --text --dismount /tmp/vc_verify_outer --non-interactive 2>/dev/null || true
else
    echo "Failed to mount outer volume."
fi
rmdir /tmp/vc_verify_outer 2>/dev/null || true

# --- Step 4: Check Outer Volume Modification Time ---
if [ -f /home/ga/Volumes/outer_vault.hc ]; then
    OUTER_MODIFIED_TIME=$(stat -c%Y /home/ga/Volumes/outer_vault.hc)
fi

# --- Write Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "volumes_dismounted_at_end": $VOLUMES_DISMOUNTED,
    "inner_volume_found": $INNER_FOUND,
    "inner_volume_size": $INNER_SIZE,
    "inner_mount_success": $INNER_MOUNT_SUCCESS,
    "inner_algorithm": "$INNER_ALGO",
    "files_found_count": $FILES_FOUND,
    "file_integrity_ok": $FILE_INTEGRITY_OK,
    "outer_modified_time": $OUTER_MODIFIED_TIME,
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="