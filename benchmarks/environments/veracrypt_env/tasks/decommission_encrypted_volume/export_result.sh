#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Decommission Task Results ==="

# Paths
EXPORT_DIR="/home/ga/Documents/DecryptedExport"
CHECKSUM_FILE="$EXPORT_DIR/checksums.sha256"
REPORT_FILE="/home/ga/Documents/decommission_report.txt"
VOLUME_PATH="/home/ga/Volumes/data_volume.hc"
ASSETS_DIR="/workspace/assets/sample_data"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Check 1: Files Exported & Integrity ---
FILES_EXPORTED_COUNT=0
FILES_INTEGRITY_MATCH=0
EXPECTED_FILES=("SF312_Nondisclosure_Agreement.txt" "FY2024_Revenue_Budget.csv" "backup_authorized_keys")

for fname in "${EXPECTED_FILES[@]}"; do
    if [ -f "$EXPORT_DIR/$fname" ]; then
        FILES_EXPORTED_COUNT=$((FILES_EXPORTED_COUNT + 1))
        
        # Check integrity against ground truth assets
        HASH_EXPORT=$(sha256sum "$EXPORT_DIR/$fname" | awk '{print $1}')
        HASH_TRUTH=$(sha256sum "$ASSETS_DIR/$fname" | awk '{print $1}')
        
        if [ "$HASH_EXPORT" == "$HASH_TRUTH" ]; then
            FILES_INTEGRITY_MATCH=$((FILES_INTEGRITY_MATCH + 1))
        fi
    fi
done

# --- Check 2: Checksum Manifest ---
MANIFEST_EXISTS="false"
MANIFEST_VALID="false"
MANIFEST_CORRECT="false"

if [ -f "$CHECKSUM_FILE" ]; then
    MANIFEST_EXISTS="true"
    # Basic format check (hash space filename)
    if grep -qE "^[a-f0-9]{64}[[:space:]]+.*" "$CHECKSUM_FILE"; then
        MANIFEST_VALID="true"
    fi
    
    # Check if hash values in manifest match the actual files
    # We count how many lines in manifest match the ground truth hashes
    MATCHING_ENTRIES=0
    for fname in "${EXPECTED_FILES[@]}"; do
        HASH_TRUTH=$(sha256sum "$ASSETS_DIR/$fname" | awk '{print $1}')
        if grep -q "$HASH_TRUTH" "$CHECKSUM_FILE"; then
            MATCHING_ENTRIES=$((MATCHING_ENTRIES + 1))
        fi
    done
    if [ "$MATCHING_ENTRIES" -ge 3 ]; then
        MANIFEST_CORRECT="true"
    fi
fi

# --- Check 3: Container Destruction ---
CONTAINER_DESTROYED="false"
CONTAINER_STATUS="exists"

if [ ! -f "$VOLUME_PATH" ]; then
    CONTAINER_DESTROYED="true"
    CONTAINER_STATUS="deleted"
else
    # File exists, check if it's mountable (if not mountable with correct password, it's effectively destroyed/overwritten)
    mkdir -p /tmp/vc_check_mount
    if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_check_mount \
        --password='MountMe2024' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        CONTAINER_DESTROYED="false"
        CONTAINER_STATUS="mountable"
        veracrypt --text --dismount /tmp/vc_check_mount --non-interactive >/dev/null 2>&1 || true
    else
        CONTAINER_DESTROYED="true"
        CONTAINER_STATUS="corrupted_or_overwritten"
    fi
    rmdir /tmp/vc_check_mount 2>/dev/null || true
fi

# --- Check 4: Volume Dismounted ---
# Check if anything is mounted at the target slot or mountpoint
VOLUME_DISMOUNTED="true"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>/dev/null || echo "")
if echo "$MOUNT_LIST" | grep -q "/home/ga/MountPoints/slot1"; then
    VOLUME_DISMOUNTED="false"
fi

# --- Check 5: Decommission Report ---
REPORT_EXISTS="false"
REPORT_CONTENT_SCORE=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    
    # Simple keyword scoring
    # Date/Time check (digits and separators)
    if [[ "$CONTENT" =~ [0-9] ]]; then REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE+1)); fi
    # Volume path check
    if [[ "$CONTENT" =~ "data_volume" ]]; then REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE+1)); fi
    # File count check
    if [[ "$CONTENT" =~ "3" ]] || [[ "$CONTENT" =~ "three" ]]; then REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE+1)); fi
    # Status check
    if [[ "$CONTENT" =~ "pass" ]]; then REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE+1)); fi
    # Destruction check
    if [[ "$CONTENT" =~ "destroyed" ]] || [[ "$CONTENT" =~ "deleted" ]] || [[ "$CONTENT" =~ "wiped" ]]; then REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE+1)); fi
fi

# --- Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- Export JSON ---
cat << EOF > /tmp/task_result.json
{
    "files_exported_count": $FILES_EXPORTED_COUNT,
    "files_integrity_match": $FILES_INTEGRITY_MATCH,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_valid": $MANIFEST_VALID,
    "manifest_correct": $MANIFEST_CORRECT,
    "container_destroyed": $CONTAINER_DESTROYED,
    "container_status": "$CONTAINER_STATUS",
    "volume_dismounted": $VOLUME_DISMOUNTED,
    "report_exists": $REPORT_EXISTS,
    "report_content_score": $REPORT_CONTENT_SCORE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy
cp /tmp/task_result.json /tmp/task_result_safe.json
chmod 666 /tmp/task_result_safe.json
mv /tmp/task_result_safe.json /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json