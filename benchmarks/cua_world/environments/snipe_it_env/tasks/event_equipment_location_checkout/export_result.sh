#!/bin/bash
echo "=== Exporting event_equipment_location_checkout results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/event_checkout_final.png

# ---------------------------------------------------------------
# Check for Location "Main Auditorium"
# ---------------------------------------------------------------
LOC_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Main Auditorium' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
LOC_FOUND="false"
if [ -n "$LOC_ID" ] && [ "$LOC_ID" != "NULL" ]; then 
    LOC_FOUND="true"
fi

# Helper function to build JSON for a specific asset
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, assigned_to, assigned_type, expected_checkin FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    
    local id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local assigned_to=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local assigned_type=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    local expected_checkin=$(echo "$data" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    
    # Get the latest checkout action note for this asset
    local note=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$id AND item_type='App\\\\Models\\\\Asset' AND action_type='checkout' ORDER BY id DESC LIMIT 1" | tr -d '\n')
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"assigned_to\": \"$assigned_to\", \"assigned_type\": \"$(json_escape "$assigned_type")\", \"expected_checkin\": \"$expected_checkin\", \"note\": \"$(json_escape "$note")\"}"
}

# ---------------------------------------------------------------
# Process Target Assets
# ---------------------------------------------------------------
TARGETS=("AV-PROJ-01" "AV-PROJ-02" "AV-MIC-01" "AV-MIC-02" "AV-MIC-03" "AV-MIC-04" "AV-SW-01")
TARGETS_JSON="["
first=true
for tag in "${TARGETS[@]}"; do
    if [ "$first" = true ]; then first=false; else TARGETS_JSON+=","; fi
    TARGETS_JSON+=$(build_asset_json "$tag")
done
TARGETS_JSON+="]"

# ---------------------------------------------------------------
# Process Unrelated Assets
# ---------------------------------------------------------------
UNRELATED=("AV-PROJ-03" "AV-MIC-05")
UNRELATED_JSON="["
first=true
for tag in "${UNRELATED[@]}"; do
    if [ "$first" = true ]; then first=false; else UNRELATED_JSON+=","; fi
    UNRELATED_JSON+=$(build_asset_json "$tag")
done
UNRELATED_JSON+="]"

# ---------------------------------------------------------------
# Build and Save Result JSON
# ---------------------------------------------------------------
RESULT_JSON=$(cat << JSONEOF
{
  "location_found": $LOC_FOUND,
  "location_id": "$LOC_ID",
  "targets": $TARGETS_JSON,
  "unrelated": $UNRELATED_JSON
}
JSONEOF
)

safe_write_result "/tmp/event_equipment_location_checkout_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/event_equipment_location_checkout_result.json"
echo "$RESULT_JSON"
echo "=== event_equipment_location_checkout export complete ==="