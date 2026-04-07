#!/bin/bash
echo "=== Exporting mobile_broadcast_kit_assembly results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Fetch Status IDs
SL_REPAIR_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')

# Fetch Users
USR_ELENA=$(snipeit_db_query "SELECT id FROM users WHERE username='erostova'" | tr -d '[:space:]')
USR_MARCUS=$(snipeit_db_query "SELECT id FROM users WHERE username='mjohnson'" | tr -d '[:space:]')
USR_SARAH=$(snipeit_db_query "SELECT id FROM users WHERE username='schen'" | tr -d '[:space:]')

# Fetch Camera IDs
CAM1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='CAM-001'" | tr -d '[:space:]')
CAM2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='CAM-002'" | tr -d '[:space:]')
CAM3_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='CAM-003'" | tr -d '[:space:]')

# Helper to get asset state
get_asset_state() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT assigned_to, assigned_type, status_id FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo '{"found": false}'
        return
    fi
    local assigned=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local atype=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local sid=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    
    # Handle NULL assignments securely
    if [ "$assigned" = "NULL" ] || [ -z "$assigned" ]; then assigned="null"; else assigned="\"$assigned\""; fi
    
    echo "{\"found\": true, \"assigned_to\": $assigned, \"assigned_type\": \"$(json_escape "$atype")\", \"status_id\": \"$sid\"}"
}

# Helper to get checkout note from action_logs for a camera
get_cam_note() {
    local cam_id="$1"
    if [ -z "$cam_id" ] || [ "$cam_id" = "NULL" ]; then
        echo ""
        return
    fi
    local log=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$cam_id AND item_type LIKE '%Asset' AND action_type='checkout' AND target_type LIKE '%User' ORDER BY id DESC LIMIT 1" | tr -d '\n')
    echo "$(json_escape "$log")"
}

# Build Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "users": {
    "elena": "${USR_ELENA:-0}",
    "marcus": "${USR_MARCUS:-0}",
    "sarah": "${USR_SARAH:-0}"
  },
  "cameras": {
    "cam1": {"id": "${CAM1_ID:-0}", "state": $(get_asset_state "CAM-001"), "note": "$(get_cam_note "$CAM1_ID")"},
    "cam2": {"id": "${CAM2_ID:-0}", "state": $(get_asset_state "CAM-002"), "note": "$(get_cam_note "$CAM2_ID")"},
    "cam3": {"id": "${CAM3_ID:-0}", "state": $(get_asset_state "CAM-003"), "note": "$(get_cam_note "$CAM3_ID")"}
  },
  "components": {
    "lens1": $(get_asset_state "LENS-001"),
    "lens2": $(get_asset_state "LENS-002"),
    "lens3": $(get_asset_state "LENS-003"),
    "mic1": $(get_asset_state "MIC-001"),
    "mic2": $(get_asset_state "MIC-002"),
    "mic3": $(get_asset_state "MIC-003"),
    "mic4": $(get_asset_state "MIC-004"),
    "bat1": $(get_asset_state "BAT-001"),
    "bat2": $(get_asset_state "BAT-002"),
    "bat3": $(get_asset_state "BAT-003")
  },
  "statuses": {
    "repair_id": "${SL_REPAIR_ID:-0}"
  }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="