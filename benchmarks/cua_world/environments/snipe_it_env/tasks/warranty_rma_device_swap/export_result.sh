#!/bin/bash
echo "=== Exporting warranty_rma_device_swap results ==="
source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/rma_final.png

SL_RETIRED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Retired' LIMIT 1" | tr -d '[:space:]')
SL_RETIRED_ID=${SL_RETIRED_ID:-0}

# Fetch asset payload Helper
get_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, status_id, assigned_to, notes, purchase_cost, purchase_date, model_id, serial FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"found\": false}"
    else
        local id=$(echo "$data" | awk -F'\t' '{print $1}')
        local status=$(echo "$data" | awk -F'\t' '{print $2}')
        local assigned=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
        local notes=$(echo "$data" | awk -F'\t' '{print $4}')
        local cost=$(echo "$data" | awk -F'\t' '{print $5}')
        local date=$(echo "$data" | awk -F'\t' '{print $6}')
        local model=$(echo "$data" | awk -F'\t' '{print $7}')
        local serial=$(echo "$data" | awk -F'\t' '{print $8}')

        local assigned_username=""
        if [ -n "$assigned" ] && [ "$assigned" != "NULL" ] && [ "$assigned" != "0" ]; then
            assigned_username=$(snipeit_db_query "SELECT username FROM users WHERE id=$assigned LIMIT 1" | tr -d '[:space:]')
        fi

        echo "{\"found\": true, \"status_id\": \"$status\", \"assigned_to\": \"$assigned\", \"assigned_username\": \"$assigned_username\", \"notes\": \"$(json_escape "$notes")\", \"purchase_cost\": \"$cost\", \"purchase_date\": \"$date\", \"model_id\": \"$model\", \"serial\": \"$(json_escape "$serial")\"}"
    fi
}

ERR1=$(get_asset_json "LPT-ERR-01")
ERR1=${ERR1:-'{"found": false}'}

ERR2=$(get_asset_json "LPT-ERR-02")
ERR2=${ERR2:-'{"found": false}'}

ERR3=$(get_asset_json "LPT-ERR-03")
ERR3=${ERR3:-'{"found": false}'}

REP1=$(get_asset_json "LPT-REP-01")
REP1=${REP1:-'{"found": false}'}

REP2=$(get_asset_json "LPT-REP-02")
REP2=${REP2:-'{"found": false}'}

REP3=$(get_asset_json "LPT-REP-03")
REP3=${REP3:-'{"found": false}'}

BASELINE=$(cat /tmp/rma_baseline.json 2>/dev/null)
BASELINE=${BASELINE:-"{}"}

RESULT_JSON=$(cat << JSONEOF
{
  "baseline": $BASELINE,
  "sl_retired_id": "$SL_RETIRED_ID",
  "old_assets": {
    "LPT-ERR-01": $ERR1,
    "LPT-ERR-02": $ERR2,
    "LPT-ERR-03": $ERR3
  },
  "new_assets": {
    "LPT-REP-01": $REP1,
    "LPT-REP-02": $REP2,
    "LPT-REP-03": $REP3
  }
}
JSONEOF
)

safe_write_result "/tmp/rma_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/rma_task_result.json"
echo "=== Export Complete ==="