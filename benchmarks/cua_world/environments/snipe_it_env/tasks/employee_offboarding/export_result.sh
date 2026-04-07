#!/bin/bash
echo "=== Exporting employee_offboarding results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/offboarding_final.png

# Read baseline
SL_READY_ID=$(cat /tmp/sl_ready_id.txt 2>/dev/null || echo "0")
SL_REPAIR_ID=$(cat /tmp/sl_repair_id.txt 2>/dev/null || echo "0")
INITIAL_OTHER_ASSET=$(cat /tmp/initial_other_asset_count.txt 2>/dev/null || echo "0")
INITIAL_OTHER_USER=$(cat /tmp/initial_other_user_count.txt 2>/dev/null || echo "0")

# Helper function to get asset JSON
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, assigned_to, status_id FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local asset_id=$(echo "$data" | awk -F'\t' '{print $1}')
    local assigned_to=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local status_id=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    
    local is_checked_in="true"
    if [ -n "$assigned_to" ] && [ "$assigned_to" != "NULL" ] && [ "$assigned_to" != "0" ]; then
        is_checked_in="false"
    fi
    
    local has_note="false"
    local note_count=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_id=${asset_id} AND item_type LIKE '%Asset%' AND LOWER(note) LIKE '%offboarding%'" | tr -d '[:space:]')
    if [ "$note_count" -gt 0 ]; then
        has_note="true"
    else
        # Also check fallback asset notes
        local asset_note=$(snipeit_db_query "SELECT LOWER(IFNULL(notes,'')) FROM assets WHERE id=${asset_id}" | tr -d '[:space:]')
        if echo "$asset_note" | grep -qi "offboarding\|offboard"; then
            has_note="true"
        fi
    fi
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"is_checked_in\": $is_checked_in, \"status_id\": \"$status_id\", \"has_note\": $has_note}"
}

SC01_JSON=$(build_asset_json "ASSET-SC01")
SC02_JSON=$(build_asset_json "ASSET-SC02")
SC03_JSON=$(build_asset_json "ASSET-SC03")
SC04_JSON=$(build_asset_json "ASSET-SC04")

# Check user status
SARAH_DELETED="false"
SARAH_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE username='schen' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$SARAH_EXISTS" = "0" ]; then
    SARAH_DELETED="true"
fi

# Check collateral damage
FINAL_OTHER_ASSET=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag NOT LIKE 'ASSET-SC0%' AND deleted_at IS NULL" | tr -d '[:space:]')
FINAL_OTHER_USER=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE username != 'schen' AND deleted_at IS NULL" | tr -d '[:space:]')

# Build comprehensive result JSON
cat > /tmp/temp_result.json << EOF
{
  "sl_ready_id": "$SL_READY_ID",
  "sl_repair_id": "$SL_REPAIR_ID",
  "SC01": $SC01_JSON,
  "SC02": $SC02_JSON,
  "SC03": $SC03_JSON,
  "SC04": $SC04_JSON,
  "sarah_deleted": $SARAH_DELETED,
  "initial_other_asset": $INITIAL_OTHER_ASSET,
  "final_other_asset": $FINAL_OTHER_ASSET,
  "initial_other_user": $INITIAL_OTHER_USER,
  "final_other_user": $FINAL_OTHER_USER
}
EOF

# Save the final export using the safe utility
safe_write_result "/tmp/employee_offboarding_result.json" "$(cat /tmp/temp_result.json)"
rm -f /tmp/temp_result.json

echo "Result saved to /tmp/employee_offboarding_result.json"
echo "=== Export complete ==="