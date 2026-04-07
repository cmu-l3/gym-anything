#!/bin/bash
echo "=== Exporting equipment_room_short_term_loans results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/equipment_room_final.png

# ---------------------------------------------------------------
# 1. Check Status Label "Short-Term Loan"
# ---------------------------------------------------------------
SL_DATA=$(snipeit_db_query "SELECT id, type, deployable FROM status_labels WHERE name='Short-Term Loan' AND deleted_at IS NULL LIMIT 1")
SL_FOUND="false"
SL_TYPE=""
SL_DEPLOYABLE=""

if [ -n "$SL_DATA" ]; then
    SL_FOUND="true"
    SL_TYPE=$(echo "$SL_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    SL_DEPLOYABLE=$(echo "$SL_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# ---------------------------------------------------------------
# 2. Check Asset States
# ---------------------------------------------------------------
get_asset_info() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.assigned_to, a.expected_checkin, a.status_id, sl.name, u.username, a.notes FROM assets a LEFT JOIN status_labels sl ON a.status_id = sl.id LEFT JOIN users u ON a.assigned_to = u.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    
    if [ -n "$data" ]; then
        local assigned=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
        local chk_date=$(echo "$data" | awk -F'\t' '{print $2}')
        local status_name=$(echo "$data" | awk -F'\t' '{print $4}')
        local username=$(echo "$data" | awk -F'\t' '{print $5}')
        local notes=$(echo "$data" | awk -F'\t' '{print $6}')

        echo "{\"found\": true, \"assigned_to_id\": \"$assigned\", \"username\": \"$username\", \"expected_checkin\": \"$chk_date\", \"status_name\": \"$(json_escape "$status_name")\", \"notes\": \"$(json_escape "$notes")\"}"
    else
        echo "{\"found\": false}"
    fi
}

MAC1_JSON=$(get_asset_info "LIB-MAC-001")
MAC2_JSON=$(get_asset_info "LIB-MAC-002")
CAM1_JSON=$(get_asset_info "LIB-CAM-001")
IPAD_JSON=$(get_asset_info "LIB-IPAD-001")

# ---------------------------------------------------------------
# 3. Check iPad Action Log for Note
# ---------------------------------------------------------------
IPAD_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LIB-IPAD-001' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
IPAD_CHECKIN_LOG=""
if [ -n "$IPAD_ID" ]; then
    IPAD_CHECKIN_LOG=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$IPAD_ID AND action_type LIKE 'checkin%' ORDER BY id DESC LIMIT 1" | tr -d '\n')
fi

# ---------------------------------------------------------------
# Build JSON Result
# ---------------------------------------------------------------
RESULT_JSON=$(cat << JSONEOF
{
  "status_label": {
    "found": $SL_FOUND,
    "type": "$(json_escape "$SL_TYPE")",
    "deployable": "$(json_escape "$SL_DEPLOYABLE")"
  },
  "assets": {
    "LIB-MAC-001": $MAC1_JSON,
    "LIB-MAC-002": $MAC2_JSON,
    "LIB-CAM-001": $CAM1_JSON,
    "LIB-IPAD-001": $IPAD_JSON
  },
  "ipad_checkin_log": "$(json_escape "$IPAD_CHECKIN_LOG")"
}
JSONEOF
)

safe_write_result "/tmp/equipment_room_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/equipment_room_result.json"
echo "$RESULT_JSON"
echo "=== equipment_room_short_term_loans export complete ==="