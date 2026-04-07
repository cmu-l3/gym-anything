#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png

# 1. Query ASSET-ENG-99 status and notes
ENG99_DATA=$(snipeit_db_query "SELECT a.status_id, sl.type, a.notes FROM assets a JOIN status_labels sl ON a.status_id = sl.id WHERE a.asset_tag='ASSET-ENG-99' AND a.deleted_at IS NULL LIMIT 1")
ENG99_STATUS_TYPE=$(echo "$ENG99_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
ENG99_NOTES=$(echo "$ENG99_DATA" | awk -F'\t' '{print $3}')

# 2. Query GPU Component creation
GPU_DATA=$(snipeit_db_query "SELECT id, qty, order_number FROM components WHERE name LIKE '%NVIDIA RTX A6000%' AND deleted_at IS NULL LIMIT 1")
GPU_ID=$(echo "$GPU_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
GPU_QTY=$(echo "$GPU_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
GPU_ORDER=$(echo "$GPU_DATA" | awk -F'\t' '{print $3}')

# 3. Query RAM Component creation
RAM_DATA=$(snipeit_db_query "SELECT id, qty, order_number FROM components WHERE name LIKE '%128GB DDR4%' AND deleted_at IS NULL LIMIT 1")
RAM_ID=$(echo "$RAM_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
RAM_QTY=$(echo "$RAM_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
RAM_ORDER=$(echo "$RAM_DATA" | awk -F'\t' '{print $3}')

# 4. Check component checkout to ASSET-ENG-42
ENG42_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-ENG-42' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

GPU_CHECKOUT_QTY=0
if [ -n "$GPU_ID" ] && [ -n "$ENG42_ID" ]; then
    # Query components_assets pivot table for assignments to the specific asset
    CHECKOUT_QTY=$(snipeit_db_query "SELECT SUM(assigned_qty) FROM components_assets WHERE component_id=$GPU_ID AND asset_id=$ENG42_ID" | tr -d '[:space:]')
    if [ -n "$CHECKOUT_QTY" ] && [ "$CHECKOUT_QTY" != "NULL" ]; then
        GPU_CHECKOUT_QTY=$CHECKOUT_QTY
    fi
fi

# Build output JSON
RESULT_JSON=$(cat << JSONEOF
{
    "eng99_status_type": "$(json_escape "$ENG99_STATUS_TYPE")",
    "eng99_notes": "$(json_escape "$ENG99_NOTES")",
    "gpu_found": $(if [ -n "$GPU_ID" ]; then echo "true"; else echo "false"; fi),
    "gpu_qty": "${GPU_QTY:-0}",
    "gpu_order": "$(json_escape "$GPU_ORDER")",
    "ram_found": $(if [ -n "$RAM_ID" ]; then echo "true"; else echo "false"; fi),
    "ram_qty": "${RAM_QTY:-0}",
    "ram_order": "$(json_escape "$RAM_ORDER")",
    "gpu_checkout_qty": ${GPU_CHECKOUT_QTY:-0}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="