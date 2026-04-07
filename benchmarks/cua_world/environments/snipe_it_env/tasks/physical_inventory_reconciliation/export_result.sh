#!/bin/bash
echo "=== Exporting physical_inventory_reconciliation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/inventory_final.png

# Read baseline values
LOC_B=$(cat /tmp/loc_b_id.txt 2>/dev/null || echo "0")
SL_LOST=$(cat /tmp/sl_lost_id.txt 2>/dev/null || echo "0")
MOD_CISCO=$(cat /tmp/mod_cisco_id.txt 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")

# Helper function to extract asset state and notes
build_audit_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, status_id, rtd_location_id, COALESCE(UNIX_TIMESTAMP(last_audit_date), 0), notes FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    
    local asset_id=$(echo "$data" | awk -F'\t' '{print $1}')
    local status_id=$(echo "$data" | awk -F'\t' '{print $2}')
    local loc_id=$(echo "$data" | awk -F'\t' '{print $3}')
    local last_audit=$(echo "$data" | awk -F'\t' '{print $4}')
    local notes=$(echo "$data" | awk -F'\t' '{print $5}')
    
    # Grab latest action log notes for this asset in case they added the note during a status change checkout/checkin
    local log_notes=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$asset_id AND item_type='App\\\\Models\\\\Asset' ORDER BY id DESC LIMIT 5" | tr '\n' ' ')
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"status_id\": \"$status_id\", \"rtd_location_id\": \"$loc_id\", \"last_audit_ts\": $last_audit, \"notes\": \"$(json_escape "$notes")\", \"log_notes\": \"$(json_escape "$log_notes")\"}"
}

echo "Extracting state for audit assets..."
AUD01=$(build_audit_json "ASSET-AUD01")
AUD02=$(build_audit_json "ASSET-AUD02")
AUD03=$(build_audit_json "ASSET-AUD03")
AUD04=$(build_audit_json "ASSET-AUD04")
AUD05=$(build_audit_json "ASSET-AUD05")

# Check if ASSET-AUD06 was created correctly
echo "Extracting state for new asset ASSET-AUD06..."
AUD06_DATA=$(snipeit_db_query "SELECT serial, model_id, rtd_location_id FROM assets WHERE asset_tag='ASSET-AUD06' AND deleted_at IS NULL LIMIT 1")
AUD06_FOUND="false"
AUD06_SERIAL=""
AUD06_MODEL=""
AUD06_LOC=""
if [ -n "$AUD06_DATA" ]; then
    AUD06_FOUND="true"
    AUD06_SERIAL=$(echo "$AUD06_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    AUD06_MODEL=$(echo "$AUD06_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    AUD06_LOC=$(echo "$AUD06_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# Get current overall asset count
CURRENT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Build final JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $START_TIME,
  "loc_b_id": "$LOC_B",
  "sl_lost_id": "$SL_LOST",
  "mod_cisco_id": "$MOD_CISCO",
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "assets": {
    "AUD01": $AUD01,
    "AUD02": $AUD02,
    "AUD03": $AUD03,
    "AUD04": $AUD04,
    "AUD05": $AUD05
  },
  "aud06": {
    "found": $AUD06_FOUND,
    "serial": "$(json_escape "$AUD06_SERIAL")",
    "model_id": "$AUD06_MODEL",
    "loc_id": "$AUD06_LOC"
  }
}
JSONEOF
)

safe_write_result "/tmp/physical_inventory_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/physical_inventory_result.json"
echo "$RESULT_JSON"
echo "=== physical_inventory_reconciliation export complete ==="