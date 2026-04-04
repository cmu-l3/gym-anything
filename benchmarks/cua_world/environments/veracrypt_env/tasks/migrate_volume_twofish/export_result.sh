#!/bin/bash
echo "=== Exporting migrate_volume_twofish results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DEST_VOL="/home/ga/Volumes/twofish_volume.hc"
MANIFEST="/home/ga/Documents/migration_manifest.txt"
RESULT_JSON="/tmp/task_result.json"

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# --- Check 1: Destination Volume Existence & Properties ---
VOL_EXISTS="false"
VOL_SIZE=0
VOL_CREATED_AFTER_START="false"
ALGO_IS_TWOFISH="false"
VOL_MOUNTABLE="false"
FILES_MATCH="false"
FILES_FOUND=()

if [ -f "$DEST_VOL" ]; then
    VOL_EXISTS="true"
    VOL_SIZE=$(stat -c%s "$DEST_VOL")
    VOL_MTIME=$(stat -c%Y "$DEST_VOL")
    
    if [ "$VOL_MTIME" -ge "$TASK_START" ]; then
        VOL_CREATED_AFTER_START="true"
    fi

    # Attempt to mount destination volume to verify password and algo
    mkdir -p /tmp/vc_verify
    MOUNT_OUTPUT=$(veracrypt --text --mount "$DEST_VOL" /tmp/vc_verify \
        --password='SecureMigration2024!' --pim=0 --keyfiles='' \
        --protect-hidden=no --non-interactive 2>&1)
    
    if mountpoint -q /tmp/vc_verify; then
        VOL_MOUNTABLE="true"
        
        # Check Encryption Algorithm
        VOL_INFO=$(veracrypt --text --volume-properties "$DEST_VOL" 2>/dev/null)
        if echo "$VOL_INFO" | grep -i "Encryption Algorithm" | grep -qi "Twofish"; then
            ALGO_IS_TWOFISH="true"
        fi

        # Check Contents
        # Load ground truth
        GT_JSON=$(cat /var/lib/veracrypt_ground_truth/source_files.json 2>/dev/null || echo "{}")
        
        # Verify files
        MATCH_COUNT=0
        TOTAL_GT=$(echo "$GT_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
        
        # We need to export the file list for Python verification later, 
        # or do a quick check here. Let's list what we found.
        cd /tmp/vc_verify
        for f in *; do
            if [ -f "$f" ]; then
                FSIZE=$(stat -c%s "$f")
                FILES_FOUND+=("{\"name\": \"$f\", \"size\": $FSIZE}")
            fi
        done
        cd - > /dev/null

        # Dismount
        veracrypt --text --dismount /tmp/vc_verify --non-interactive 2>/dev/null || true
    fi
    rmdir /tmp/vc_verify 2>/dev/null || true
fi

# --- Check 2: Manifest File ---
MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""
if [ -f "$MANIFEST" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST" | head -c 1000) # Limit size
fi

# --- Check 3: Clean Dismount ---
# Check if any volumes are currently mounted
OPEN_MOUNTS=$(veracrypt --text --list 2>/dev/null | grep -c "Slot" || echo "0")
ALL_DISMOUNTED="false"
if [ "$OPEN_MOUNTS" -eq 0 ]; then
    ALL_DISMOUNTED="true"
fi

# --- Check 4: Source Volume Integrity ---
SOURCE_INTACT="false"
mkdir -p /tmp/vc_src_check
if veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_src_check \
    --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive >/dev/null 2>&1; then
    SOURCE_INTACT="true"
    veracrypt --text --dismount /tmp/vc_src_check --non-interactive >/dev/null 2>&1 || true
fi
rmdir /tmp/vc_src_check 2>/dev/null || true

# Construct JSON Array of found files
FILES_JSON="["
for i in "${!FILES_FOUND[@]}"; do
    FILES_JSON+="${FILES_FOUND[$i]}"
    if [ $i -lt $((${#FILES_FOUND[@]}-1)) ]; then
        FILES_JSON+=","
    fi
done
FILES_JSON+="]"

# Write Result JSON
cat > /tmp/task_result_temp.json <<EOF
{
    "volume_exists": $VOL_EXISTS,
    "volume_size": $VOL_SIZE,
    "created_during_task": $VOL_CREATED_AFTER_START,
    "is_twofish": $ALGO_IS_TWOFISH,
    "is_mountable": $VOL_MOUNTABLE,
    "files_found": $FILES_JSON,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_content": $(python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$MANIFEST_CONTENT"),
    "all_dismounted": $ALL_DISMOUNTED,
    "source_intact": $SOURCE_INTACT,
    "ground_truth": $(cat /var/lib/veracrypt_ground_truth/source_files.json 2>/dev/null || echo "{}")
}
EOF

write_result_json "$RESULT_JSON" "$(cat /tmp/task_result_temp.json)"
rm -f /tmp/task_result_temp.json

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="