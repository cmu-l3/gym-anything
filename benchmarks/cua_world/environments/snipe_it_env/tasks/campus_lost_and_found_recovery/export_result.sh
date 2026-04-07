#!/bin/bash
echo "=== Exporting campus_lost_and_found_recovery results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load baselines
A1_ID=$(cat /tmp/lf_a1_id.txt 2>/dev/null || echo "0")
A2_ID=$(cat /tmp/lf_a2_id.txt 2>/dev/null || echo "0")
A3_ID=$(cat /tmp/lf_a3_id.txt 2>/dev/null || echo "0")
INITIAL_ASSET_COUNT=$(cat /tmp/lf_initial_asset_count.txt 2>/dev/null || echo "0")
CURRENT_ASSET_COUNT=$(get_asset_count)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Location
LOC_DATA=$(snipeit_db_query "SELECT id FROM locations WHERE name='Security Holding' AND deleted_at IS NULL LIMIT 1")
LOC_FOUND="false"
LOC_ID="null"
if [ -n "$LOC_DATA" ]; then
    LOC_FOUND="true"
    LOC_ID=$(echo "$LOC_DATA" | tr -d '[:space:]')
fi

# 2. Check Status Label
STATUS_DATA=$(snipeit_db_query "SELECT id, deployable, pending, archived FROM status_labels WHERE name='Recovered - Holding' AND deleted_at IS NULL LIMIT 1")
STATUS_FOUND="false"
STATUS_ID="null"
STATUS_DEPLOYABLE="1"
STATUS_PENDING="0"
STATUS_ARCHIVED="0"

if [ -n "$STATUS_DATA" ]; then
    STATUS_FOUND="true"
    STATUS_ID=$(echo "$STATUS_DATA" | awk -F'\t' '{print $1}')
    STATUS_DEPLOYABLE=$(echo "$STATUS_DATA" | awk -F'\t' '{print $2}')
    STATUS_PENDING=$(echo "$STATUS_DATA" | awk -F'\t' '{print $3}')
    STATUS_ARCHIVED=$(echo "$STATUS_DATA" | awk -F'\t' '{print $4}')
fi

# 3. Helper to dump asset state
get_asset_json() {
    local target_id="$1"
    local data=$(snipeit_db_query "SELECT id, status_id, rtd_location_id, assigned_to FROM assets WHERE id=$target_id AND deleted_at IS NULL LIMIT 1")
    
    if [ -z "$data" ]; then
        echo '{"found": false}'
    else
        local aid=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
        local s_id=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
        local l_id=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
        local assigned=$(echo "$data" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
        
        local is_assigned="false"
        if [ -n "$assigned" ] && [ "$assigned" != "NULL" ] && [ "$assigned" != "0" ]; then
            is_assigned="true"
        fi
        
        echo "{\"found\": true, \"status_id\": \"${s_id}\", \"location_id\": \"${l_id}\", \"is_assigned\": ${is_assigned}}"
    fi
}

A1_JSON=$(get_asset_json "$A1_ID")
A2_JSON=$(get_asset_json "$A2_ID")
A3_JSON=$(get_asset_json "$A3_ID")

# 4. Check action logs for the required checkin note
NOTE="Recovered by Campus Security"
NOTE_ESCAPED=$(snipeit_db_query "SELECT quote('$NOTE')" | tr -d '[:space:]' | sed "s/^'//;s/'$//")

# Count checkin logs with this exact note (case insensitive match via LIKE)
CHECKIN_NOTES_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='checkin from' AND notes LIKE '%Recovered by Campus Security%'" | tr -d '[:space:]')

# Check if specific assets have this note
A1_HAS_NOTE=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_id=$A1_ID AND item_type='App\\\\Models\\\\Asset' AND action_type='checkin from' AND notes LIKE '%Recovered by Campus Security%'" | tr -d '[:space:]')
A3_HAS_NOTE=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_id=$A3_ID AND item_type='App\\\\Models\\\\Asset' AND action_type='checkin from' AND notes LIKE '%Recovered by Campus Security%'" | tr -d '[:space:]')

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "location": {
    "found": $LOC_FOUND,
    "id": $LOC_ID
  },
  "status_label": {
    "found": $STATUS_FOUND,
    "id": $STATUS_ID,
    "deployable": $STATUS_DEPLOYABLE,
    "pending": $STATUS_PENDING,
    "archived": $STATUS_ARCHIVED
  },
  "assets": {
    "device_1": $A1_JSON,
    "device_2": $A2_JSON,
    "device_3": $A3_JSON
  },
  "logs": {
    "total_checkin_notes_count": ${CHECKIN_NOTES_COUNT:-0},
    "a1_has_note": ${A1_HAS_NOTE:-0},
    "a3_has_note": ${A3_HAS_NOTE:-0}
  },
  "anti_gaming": {
    "initial_asset_count": $INITIAL_ASSET_COUNT,
    "current_asset_count": $CURRENT_ASSET_COUNT
  }
}
JSONEOF
)

safe_write_result "/tmp/lost_and_found_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/lost_and_found_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="