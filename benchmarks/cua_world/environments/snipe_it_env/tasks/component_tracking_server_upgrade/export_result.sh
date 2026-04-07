#!/bin/bash
echo "=== Exporting component_tracking_server_upgrade results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Read variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COMP_COUNT=$(cat /tmp/initial_component_count.txt 2>/dev/null || echo "0")
SVR1_ID=$(cat /tmp/svr1_asset_id.txt 2>/dev/null || echo "0")
SVR2_ID=$(cat /tmp/svr2_asset_id.txt 2>/dev/null || echo "0")
AUSTIN_LOC_ID=$(cat /tmp/austin_loc_id.txt 2>/dev/null || echo "0")

# Check Category
CAT_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM categories WHERE name='Server Memory' AND category_type='component' AND deleted_at IS NULL" | tr -d '[:space:]')
WRONG_TYPE_CAT=$(snipeit_db_query "SELECT COUNT(*) FROM categories WHERE name='Server Memory' AND category_type!='component' AND deleted_at IS NULL" | tr -d '[:space:]')

# Helper to get component JSON
get_component_json() {
    local pattern="$1"
    local data=$(snipeit_db_query "SELECT id, qty, min_amt, purchase_cost, location_id, created_at FROM components WHERE name LIKE '%${pattern}%' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"found\": false}"
        return
    fi
    
    local id=$(echo "$data" | awk -F'\t' '{print $1}')
    local qty=$(echo "$data" | awk -F'\t' '{print $2}')
    local min_amt=$(echo "$data" | awk -F'\t' '{print $3}')
    local cost=$(echo "$data" | awk -F'\t' '{print $4}')
    local loc_id=$(echo "$data" | awk -F'\t' '{print $5}')
    local created_at=$(echo "$data" | awk -F'\t' '{print $6}')
    
    local loc_name=""
    if [ -n "$loc_id" ] && [ "$loc_id" != "NULL" ]; then
        loc_name=$(snipeit_db_query "SELECT name FROM locations WHERE id=$loc_id" | tr -d '\n')
    fi
    
    # Check if created after task start
    local created_ts=$(date -d "$created_at" +%s 2>/dev/null || echo "0")
    local created_during_task="false"
    if [ "$created_ts" -ge "$TASK_START" ]; then
        created_during_task="true"
    fi
    
    echo "{\"found\": true, \"id\": \"$id\", \"qty\": \"$qty\", \"min_amt\": \"$min_amt\", \"cost\": \"$cost\", \"loc_id\": \"$loc_id\", \"loc_name\": \"$(json_escape "$loc_name")\", \"created_during_task\": $created_during_task}"
}

SAMSUNG_JSON=$(get_component_json "Samsung%32GB")
KINGSTON_JSON=$(get_component_json "Kingston%64GB")

# Extract IDs to check checkouts
SAMSUNG_ID=$(echo "$SAMSUNG_JSON" | grep -o '"id": "[0-9]*"' | grep -o '[0-9]*' || echo "0")
KINGSTON_ID=$(echo "$KINGSTON_JSON" | grep -o '"id": "[0-9]*"' | grep -o '[0-9]*' || echo "0")

# Check Samsung Checkout to SVR-UPG-001
SAMSUNG_CHECKOUT_QTY="0"
if [ "$SAMSUNG_ID" != "0" ] && [ "$SVR1_ID" != "0" ]; then
    SAMSUNG_CHECKOUT_QTY=$(snipeit_db_query "SELECT COALESCE(SUM(assigned_qty), 0) FROM components_assets WHERE component_id=$SAMSUNG_ID AND asset_id=$SVR1_ID" | tr -d '[:space:]')
fi

# Check Kingston Checkout to SVR-UPG-002
KINGSTON_CHECKOUT_QTY="0"
if [ "$KINGSTON_ID" != "0" ] && [ "$SVR2_ID" != "0" ]; then
    KINGSTON_CHECKOUT_QTY=$(snipeit_db_query "SELECT COALESCE(SUM(assigned_qty), 0) FROM components_assets WHERE component_id=$KINGSTON_ID AND asset_id=$SVR2_ID" | tr -d '[:space:]')
fi

# Build Results
RESULT_JSON=$(cat << JSONEOF
{
    "category": {
        "exists_as_component": $([ "$CAT_EXISTS" -gt 0 ] && echo "true" || echo "false"),
        "exists_as_wrong_type": $([ "$WRONG_TYPE_CAT" -gt 0 ] && echo "true" || echo "false")
    },
    "samsung": $SAMSUNG_JSON,
    "kingston": $KINGSTON_JSON,
    "checkouts": {
        "samsung_svr1_qty": $SAMSUNG_CHECKOUT_QTY,
        "kingston_svr2_qty": $KINGSTON_CHECKOUT_QTY
    },
    "austin_loc_id": "$AUSTIN_LOC_ID"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="