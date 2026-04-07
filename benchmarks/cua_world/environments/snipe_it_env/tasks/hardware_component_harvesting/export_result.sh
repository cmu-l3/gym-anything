#!/bin/bash
echo "=== Exporting hardware_component_harvesting results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/hardware_component_harvesting_final.png

# 1. Check Status Label existence and type
SL_DATA=$(snipeit_db_query "SELECT id, type FROM status_labels WHERE name LIKE '%Pending E-Waste%' AND deleted_at IS NULL LIMIT 1")
EWASTE_EXISTS="false"
EWASTE_TYPE=""
if [ -n "$SL_DATA" ]; then
    EWASTE_EXISTS="true"
    EWASTE_TYPE=$(echo "$SL_DATA" | awk -F'\t' '{print $2}')
fi

# 2. Function to extract asset state
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.id, sl.name, l.name FROM assets a LEFT JOIN status_labels sl ON a.status_id=sl.id LEFT JOIN locations l ON a.rtd_location_id=l.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    
    local asset_id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local status_name=$(echo "$data" | awk -F'\t' '{print $2}')
    local loc_name=$(echo "$data" | awk -F'\t' '{print $3}')
    
    local comp_count=$(snipeit_db_query "SELECT SUM(assigned_qty) FROM components_assets WHERE asset_id=$asset_id" | tr -d '[:space:]')
    if [ -z "$comp_count" ] || [ "$comp_count" == "NULL" ]; then comp_count=0; fi
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"status_name\": \"$(json_escape "$status_name")\", \"location\": \"$(json_escape "$loc_name")\", \"comp_count\": $comp_count}"
}

# 3. Get state for all target assets
TRG001=$(build_asset_json "TRG-001")
TRG002=$(build_asset_json "TRG-002")
TRG003=$(build_asset_json "TRG-003")
TRG004=$(build_asset_json "TRG-004")
TRG005=$(build_asset_json "TRG-005")

# 4. Check component inventory pool logic (optional guardrail check)
REMAINING_RAM=$(snipeit_db_query "SELECT num_remaining FROM components WHERE name='16GB RAM DDR4' LIMIT 1" | tr -d '[:space:]')

# Build the result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "status_label": {
    "exists": $EWASTE_EXISTS,
    "type": "$(json_escape "$EWASTE_TYPE")"
  },
  "assets": {
    "TRG-001": $TRG001,
    "TRG-002": $TRG002,
    "TRG-003": $TRG003,
    "TRG-004": $TRG004,
    "TRG-005": $TRG005
  },
  "remaining_ram": ${REMAINING_RAM:-0}
}
JSONEOF
)

safe_write_result "/tmp/hardware_component_harvesting_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/hardware_component_harvesting_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="