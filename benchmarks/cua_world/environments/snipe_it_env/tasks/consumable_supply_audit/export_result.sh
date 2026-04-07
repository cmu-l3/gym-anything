#!/bin/bash
set -e
echo "=== Exporting consumable_supply_audit task result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Read IDs
JSMITH_ID=$(cat /tmp/jsmith_id.txt 2>/dev/null || echo "0")
AJOHNSON_ID=$(cat /tmp/ajohnson_id.txt 2>/dev/null || echo "0")
FLASH_ID=$(cat /tmp/flash_drive_id.txt 2>/dev/null || echo "0")
BATTERY_ID=$(cat /tmp/battery_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_consumable_count.txt 2>/dev/null || echo "0")

# Get current count
FINAL_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM consumables WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Check how many were created after task start
CREATED_AFTER_START=$(snipeit_db_query "SELECT COUNT(*) FROM consumables WHERE created_at >= FROM_UNIXTIME(${TASK_START}) AND deleted_at IS NULL" | tr -d '[:space:]')

# ---------------------------------------------------------------
# Extract New Consumables
# ---------------------------------------------------------------
extract_consumable() {
    local pattern="$1"
    local data=$(snipeit_db_query "SELECT id, qty, min_amt, purchase_cost, model_number, order_number, name FROM consumables WHERE name LIKE '%${pattern}%' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"found\": false}"
    else
        local id=$(echo "$data" | awk -F'\t' '{print $1}')
        local qty=$(echo "$data" | awk -F'\t' '{print $2}')
        local min_amt=$(echo "$data" | awk -F'\t' '{print $3}')
        local cost=$(echo "$data" | awk -F'\t' '{print $4}')
        local model=$(echo "$data" | awk -F'\t' '{print $5}')
        local order=$(echo "$data" | awk -F'\t' '{print $6}')
        local name=$(echo "$data" | awk -F'\t' '{print $7}')
        
        echo "{\"found\": true, \"id\": ${id:-0}, \"qty\": ${qty:-0}, \"min_amt\": ${min_amt:-0}, \"cost\": ${cost:-0}, \"model\": \"$(json_escape "$model")\", \"order\": \"$(json_escape "$order")\", \"name\": \"$(json_escape "$name")\"}"
    fi
}

INK_JSON=$(extract_consumable "HP 61XL")
CABLE_JSON=$(extract_consumable "Cat6")
ADAPTER_JSON=$(extract_consumable "USB-C Adapter")

# Get IDs for checkout checks
INK_ID=$(echo "$INK_JSON" | grep -o '"id": [0-9]*' | grep -o '[0-9]*' || echo "0")
CABLE_ID=$(echo "$CABLE_JSON" | grep -o '"id": [0-9]*' | grep -o '[0-9]*' || echo "0")

# ---------------------------------------------------------------
# Extract Checkouts
# Snipe-IT tracks consumable checkouts in consumables_users table
# (or action_logs, but consumables_users is the source of truth)
# ---------------------------------------------------------------
INK_CHECKOUTS_JSMITH=0
if [ "$INK_ID" != "0" ] && [ "$JSMITH_ID" != "0" ]; then
    INK_CHECKOUTS_JSMITH=$(snipeit_db_query "SELECT COUNT(*) FROM consumables_users WHERE consumable_id=${INK_ID} AND assigned_to=${JSMITH_ID}" | tr -d '[:space:]')
fi

CABLE_CHECKOUTS_AJOHNSON=0
if [ "$CABLE_ID" != "0" ] && [ "$AJOHNSON_ID" != "0" ]; then
    CABLE_CHECKOUTS_AJOHNSON=$(snipeit_db_query "SELECT COUNT(*) FROM consumables_users WHERE consumable_id=${CABLE_ID} AND assigned_to=${AJOHNSON_ID}" | tr -d '[:space:]')
fi

# ---------------------------------------------------------------
# Extract Existing Consumables
# ---------------------------------------------------------------
FLASH_DATA=$(snipeit_db_query "SELECT min_amt, qty, name FROM consumables WHERE id=${FLASH_ID} AND deleted_at IS NULL LIMIT 1")
FLASH_MIN=$(echo "$FLASH_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
FLASH_QTY=$(echo "$FLASH_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
FLASH_NAME=$(echo "$FLASH_DATA" | awk -F'\t' '{print $3}')

BATTERY_DATA=$(snipeit_db_query "SELECT min_amt, qty, name FROM consumables WHERE id=${BATTERY_ID} AND deleted_at IS NULL LIMIT 1")
BATTERY_MIN=$(echo "$BATTERY_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
BATTERY_QTY=$(echo "$BATTERY_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
BATTERY_NAME=$(echo "$BATTERY_DATA" | awk -F'\t' '{print $3}')

# Build result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "final_count": ${FINAL_COUNT:-0},
    "created_after_start": ${CREATED_AFTER_START:-0},
    "ink": $INK_JSON,
    "cable": $CABLE_JSON,
    "adapter": $ADAPTER_JSON,
    "ink_checkouts_jsmith": ${INK_CHECKOUTS_JSMITH:-0},
    "cable_checkouts_ajohnson": ${CABLE_CHECKOUTS_AJOHNSON:-0},
    "flash_drive": {
        "min_amt": ${FLASH_MIN:-0},
        "qty": ${FLASH_QTY:-0},
        "name": "$(json_escape "$FLASH_NAME")"
    },
    "batteries": {
        "min_amt": ${BATTERY_MIN:-0},
        "qty": ${BATTERY_QTY:-0},
        "name": "$(json_escape "$BATTERY_NAME")"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="