#!/bin/bash
echo "=== Exporting Reactivate Records Result ==="

source /workspace/scripts/task_utils.sh

DB_NAME="DrTuxTest"
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Read the target GUIDs we saved during setup
if [ ! -f /tmp/target_guids.txt ]; then
    echo "ERROR: Target GUIDs file missing."
    exit 1
fi

mapfile -t TARGET_GUIDS < /tmp/target_guids.txt
TOTAL_TARGETS=${#TARGET_GUIDS[@]}

echo "Verifying ${TOTAL_TARGETS} target patients..."

# Initialize counters
RESTORED_DATA_COUNT=0
RESTORED_INDEX_COUNT=0
REMOVED_FROM_ARCHIVE_COUNT=0
DATA_INTEGRITY_ERRORS=0

# Check each target
details="[]"

for guid in "${TARGET_GUIDS[@]}"; do
    # 1. Check fchpat (Data Table)
    in_data=$(mysql -u root $DB_NAME -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_GUID_Doss='$guid'")
    
    # 2. Check IndexNomPrenom (Index Table)
    # Must have type 'Dossier' to be visible in MedinTux
    in_index=$(mysql -u root $DB_NAME -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid' AND FchGnrl_Type='Dossier'")
    
    # 3. Check ArchivedPatients (Should be gone)
    in_archive=$(mysql -u root $DB_NAME -N -e "SELECT COUNT(*) FROM ArchivedPatients WHERE GUID='$guid'")
    
    if [ "$in_data" -gt 0 ]; then ((RESTORED_DATA_COUNT++)); fi
    if [ "$in_index" -gt 0 ]; then ((RESTORED_INDEX_COUNT++)); fi
    if [ "$in_archive" -eq 0 ]; then ((REMOVED_FROM_ARCHIVE_COUNT++)); fi

    # Accumulate details for JSON
    # (Simple append, ideally would use jq but avoiding dependencies)
done

# 4. Check for Collateral Damage
# Count how many records remain in Archive. We started with 10, removed 3 targets. Should be 7.
ARCHIVE_REMAINING=$(mysql -u root $DB_NAME -N -e "SELECT COUNT(*) FROM ArchivedPatients")
EXPECTED_REMAINING=7

COLLATERAL_DAMAGE="false"
if [ "$ARCHIVE_REMAINING" -ne "$EXPECTED_REMAINING" ]; then
    # If remaining is NOT 7, either they deleted too many or didn't delete the targets
    # We already counted targets removed.
    # If targets removed (3) and remaining != 7, they touched others.
    if [ "$REMOVED_FROM_ARCHIVE_COUNT" -eq 3 ] && [ "$ARCHIVE_REMAINING" -ne 7 ]; then
        COLLATERAL_DAMAGE="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "total_targets": $TOTAL_TARGETS,
    "restored_to_data_table_count": $RESTORED_DATA_COUNT,
    "restored_to_index_table_count": $RESTORED_INDEX_COUNT,
    "removed_from_archive_count": $REMOVED_FROM_ARCHIVE_COUNT,
    "archive_remaining_count": $ARCHIVE_REMAINING,
    "expected_archive_remaining": $EXPECTED_REMAINING,
    "collateral_damage": $COLLATERAL_DAMAGE,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="