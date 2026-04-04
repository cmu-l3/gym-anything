#!/bin/bash
echo "=== Exporting create_asset results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_asset_final.png

# Read initial state
INITIAL_ASSET_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")
MAX_ASSET_ID=$(cat /tmp/max_asset_id.txt 2>/dev/null || echo "0")

# Get current asset count
CURRENT_ASSET_COUNT=$(get_asset_count)

# Search for the expected asset by tag
ASSET_DATA=$(snipeit_db_query "SELECT id, asset_tag, name, serial, model_id, status_id, purchase_date, purchase_cost, warranty_months, supplier_id, rtd_location_id, notes FROM assets WHERE asset_tag='ASSET-L011' AND deleted_at IS NULL LIMIT 1")

ASSET_FOUND="false"
ASSET_ID=""
ASSET_TAG=""
ASSET_NAME=""
ASSET_SERIAL=""
ASSET_MODEL_ID=""
ASSET_STATUS_ID=""
ASSET_PURCHASE_DATE=""
ASSET_PURCHASE_COST=""
ASSET_WARRANTY=""
ASSET_SUPPLIER_ID=""
ASSET_LOCATION_ID=""
ASSET_NOTES=""

if [ -n "$ASSET_DATA" ]; then
    ASSET_FOUND="true"
    ASSET_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $1}')
    ASSET_TAG=$(echo "$ASSET_DATA" | awk -F'\t' '{print $2}')
    ASSET_NAME=$(echo "$ASSET_DATA" | awk -F'\t' '{print $3}')
    ASSET_SERIAL=$(echo "$ASSET_DATA" | awk -F'\t' '{print $4}')
    ASSET_MODEL_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $5}')
    ASSET_STATUS_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $6}')
    ASSET_PURCHASE_DATE=$(echo "$ASSET_DATA" | awk -F'\t' '{print $7}')
    ASSET_PURCHASE_COST=$(echo "$ASSET_DATA" | awk -F'\t' '{print $8}')
    ASSET_WARRANTY=$(echo "$ASSET_DATA" | awk -F'\t' '{print $9}')
    ASSET_SUPPLIER_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $10}')
    ASSET_LOCATION_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $11}')
    ASSET_NOTES=$(echo "$ASSET_DATA" | awk -F'\t' '{print $12}')

    # Resolve model name
    ASSET_MODEL_NAME=$(snipeit_db_query "SELECT name FROM models WHERE id=${ASSET_MODEL_ID}" | tr -d '\n')
    # Resolve status name
    ASSET_STATUS_NAME=$(snipeit_db_query "SELECT name FROM status_labels WHERE id=${ASSET_STATUS_ID}" | tr -d '\n')
    # Resolve supplier name
    ASSET_SUPPLIER_NAME=$(snipeit_db_query "SELECT name FROM suppliers WHERE id=${ASSET_SUPPLIER_ID}" | tr -d '\n' 2>/dev/null || echo "")
    # Resolve location name
    ASSET_LOCATION_NAME=$(snipeit_db_query "SELECT name FROM locations WHERE id=${ASSET_LOCATION_ID}" | tr -d '\n' 2>/dev/null || echo "")
else
    # Fallback: search for any new asset
    FALLBACK_DATA=$(snipeit_db_query "SELECT id, asset_tag, name, serial, model_id, status_id FROM assets WHERE id > ${MAX_ASSET_ID} AND deleted_at IS NULL ORDER BY id DESC LIMIT 1")
    if [ -n "$FALLBACK_DATA" ]; then
        echo "Asset ASSET-L011 not found, but found new asset: $FALLBACK_DATA"
        ASSET_ID=$(echo "$FALLBACK_DATA" | awk -F'\t' '{print $1}')
        ASSET_TAG=$(echo "$FALLBACK_DATA" | awk -F'\t' '{print $2}')
        ASSET_NAME=$(echo "$FALLBACK_DATA" | awk -F'\t' '{print $3}')
    fi
    ASSET_MODEL_NAME=""
    ASSET_STATUS_NAME=""
    ASSET_SUPPLIER_NAME=""
    ASSET_LOCATION_NAME=""
fi

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "asset_found": ${ASSET_FOUND},
  "asset_id": "${ASSET_ID}",
  "asset_tag": "$(json_escape "$ASSET_TAG")",
  "asset_name": "$(json_escape "$ASSET_NAME")",
  "serial": "$(json_escape "$ASSET_SERIAL")",
  "model_name": "$(json_escape "$ASSET_MODEL_NAME")",
  "status_name": "$(json_escape "$ASSET_STATUS_NAME")",
  "purchase_date": "${ASSET_PURCHASE_DATE}",
  "purchase_cost": "${ASSET_PURCHASE_COST}",
  "warranty_months": "${ASSET_WARRANTY}",
  "supplier_name": "$(json_escape "$ASSET_SUPPLIER_NAME")",
  "location_name": "$(json_escape "$ASSET_LOCATION_NAME")",
  "notes": "$(json_escape "$ASSET_NOTES")",
  "initial_asset_count": ${INITIAL_ASSET_COUNT},
  "current_asset_count": ${CURRENT_ASSET_COUNT},
  "max_asset_id_before": ${MAX_ASSET_ID}
}
JSONEOF
)

safe_write_result "/tmp/create_asset_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_asset_result.json"
echo "$RESULT_JSON"
echo "=== create_asset export complete ==="
