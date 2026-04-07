#!/bin/bash
echo "=== Exporting industrial_asset_inventory_digitization Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
sleep 1

# Extract Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# =====================================================================
# Database Queries to check for expected records
# =====================================================================
log "Querying database for expected asset categories..."
CAT_RADIO=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assetcategories WHERE categoryname='Two-Way Radios';" | tr -d '[:space:]')
CAT_GAS=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assetcategories WHERE categoryname='Gas Detectors';" | tr -d '[:space:]')
CAT_THERMAL=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assetcategories WHERE categoryname='Thermal Cameras';" | tr -d '[:space:]')

log "Querying database for expected vendor..."
VENDOR_COUNT=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assetvendors WHERE vendorname LIKE '%Industrial Safety Supply%';" | tr -d '[:space:]')

log "Querying database for expected assets by serial number..."
ASSET_RAD=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assets WHERE serialnumber='RAD-8821-A';" | tr -d '[:space:]')
ASSET_GAS=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assets WHERE serialnumber='GAS-9910-B';" | tr -d '[:space:]')
ASSET_THM=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_assets WHERE serialnumber='THM-4450-C';" | tr -d '[:space:]')

# =====================================================================
# Anti-Gaming: Check Apache Logs for UI Interaction
# =====================================================================
# Count POST requests to the index.php endpoint which handles form submissions
POST_COUNT=$(grep "POST /index.php" /var/log/apache2/sentrifugo_access.log 2>/dev/null | wc -l || echo "0")

# =====================================================================
# Export to JSON
# =====================================================================
TEMP_JSON=$(mktemp /tmp/asset_task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "categories": {
        "Two-Way Radios": ${CAT_RADIO:-0},
        "Gas Detectors": ${CAT_GAS:-0},
        "Thermal Cameras": ${CAT_THERMAL:-0}
    },
    "vendor_count": ${VENDOR_COUNT:-0},
    "assets": {
        "RAD-8821-A": ${ASSET_RAD:-0},
        "GAS-9910-B": ${ASSET_GAS:-0},
        "THM-4450-C": ${ASSET_THM:-0}
    },
    "post_requests": ${POST_COUNT:-0}
}
EOF

# Move temp file to final location safely
rm -f /tmp/asset_task_result.json 2>/dev/null || sudo rm -f /tmp/asset_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/asset_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/asset_task_result.json
chmod 666 /tmp/asset_task_result.json 2>/dev/null || sudo chmod 666 /tmp/asset_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/asset_task_result.json"
cat /tmp/asset_task_result.json

echo "=== Export Complete ==="