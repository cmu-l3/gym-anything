#!/bin/bash
# Export script for Inventory Scarcity Config task

echo "=== Exporting Inventory Scarcity Config Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper to get config value
get_config() {
    local path="$1"
    magento_query "SELECT value FROM core_config_data WHERE path='$path'" 2>/dev/null | tail -1
}

# 1. Query Current Configuration
echo "Querying final configuration state..."

# Backorders: 0=No, 1=Allow, 2=Allow and Notify
FINAL_BACKORDERS=$(get_config "cataloginventory/item_options/backorders")

# Threshold: Integer
FINAL_THRESHOLD=$(get_config "cataloginventory/options/stock_threshold_qty")

# Show Out of Stock: 0=No, 1=Yes
FINAL_SHOW_OOS=$(get_config "cataloginventory/options/show_out_of_stock")

# Allow Alerts: 0=No, 1=Yes
FINAL_ALERTS=$(get_config "catalog/productalert/allow_stock")

echo "Final values:"
echo "  Backorders: $FINAL_BACKORDERS"
echo "  Threshold: $FINAL_THRESHOLD"
echo "  Show OOS: $FINAL_SHOW_OOS"
echo "  Alerts: $FINAL_ALERTS"

# 2. Retrieve Initial Configuration (for comparison)
INIT_BACKORDERS="0"
INIT_THRESHOLD="0"
INIT_SHOW_OOS="0"
INIT_ALERTS="0"

if [ -f /tmp/initial_config_state.json ]; then
    INIT_BACKORDERS=$(jq -r .backorders /tmp/initial_config_state.json 2>/dev/null || echo "0")
    INIT_THRESHOLD=$(jq -r .threshold /tmp/initial_config_state.json 2>/dev/null || echo "0")
    INIT_SHOW_OOS=$(jq -r .show_out_of_stock /tmp/initial_config_state.json 2>/dev/null || echo "0")
    INIT_ALERTS=$(jq -r .allow_alert /tmp/initial_config_state.json 2>/dev/null || echo "0")
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/inventory_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial": {
        "backorders": "${INIT_BACKORDERS}",
        "threshold": "${INIT_THRESHOLD}",
        "show_out_of_stock": "${INIT_SHOW_OOS}",
        "allow_alert": "${INIT_ALERTS}"
    },
    "final": {
        "backorders": "${FINAL_BACKORDERS}",
        "threshold": "${FINAL_THRESHOLD}",
        "show_out_of_stock": "${FINAL_SHOW_OOS}",
        "allow_alert": "${FINAL_ALERTS}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
safe_write_json "$TEMP_JSON" /tmp/inventory_config_result.json

echo ""
cat /tmp/inventory_config_result.json
echo ""
echo "=== Export Complete ==="