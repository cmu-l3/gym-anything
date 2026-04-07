#!/bin/bash
echo "=== Exporting accidental_bulk_delete_recovery results ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/accidental_bulk_delete_recovery_final.png

LOC_MDF_ID=$(cat /tmp/target_location_id.txt 2>/dev/null || echo "0")

# Helper to fetch and format asset state
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, deleted_at, assigned_to, assigned_type FROM assets WHERE asset_tag='$tag' LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    
    local id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local deleted_at=$(echo "$data" | awk -F'\t' '{print $2}')
    local assigned_to=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    local assigned_type=$(echo "$data" | awk -F'\t' '{print $4}')
    
    # Fetch latest checkout note from action_logs
    local note=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$id AND item_type='App\\\\Models\\\\Asset' AND action_type='checkout' ORDER BY id DESC LIMIT 1" | tr -d '\n')
    
    # Format boolean deletion state
    local is_deleted="false"
    if [ "$deleted_at" != "NULL" ] && [ -n "$deleted_at" ]; then
        is_deleted="true"
    fi
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"id\": \"$id\", \"is_deleted\": $is_deleted, \"assigned_to\": \"$assigned_to\", \"assigned_type\": \"$(json_escape "$assigned_type")\", \"note\": \"$(json_escape "$note")\"}"
}

echo "Building JSON export..."

# Construct the result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "mdf_location_id": "$LOC_MDF_ID",
  "sw_core_01": $(build_asset_json "SW-CORE-01"),
  "sw_core_02": $(build_asset_json "SW-CORE-02"),
  "sw_dist_01": $(build_asset_json "SW-DIST-01"),
  "lapt_old_99": $(build_asset_json "LAPT-OLD-99")
}
JSONEOF
)

safe_write_result "/tmp/accidental_bulk_delete_recovery_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/accidental_bulk_delete_recovery_result.json"
echo "$RESULT_JSON"
echo "=== accidental_bulk_delete_recovery export complete ==="