#!/bin/bash
# Export script for Customize Shop Layout task

echo "=== Exporting Customize Shop Layout Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ============================================================
# QUERY CURRENT CONFIGURATION
# ============================================================

echo "Querying WooCommerce catalog options..."

# 1. Shop Display Mode
# Expected: 'both' (show subcategories and products)
DISPLAY_MODE=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_shop_page_display' LIMIT 1" 2>/dev/null)

# 2. Default Sorting
# Expected: 'price-desc' (Sort by price: high to low)
ORDER_BY=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_default_catalog_orderby' LIMIT 1" 2>/dev/null)

# 3. Columns per row
# Expected: 3
COLUMNS=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_catalog_columns' LIMIT 1" 2>/dev/null)

# 4. Rows per page
# Expected: 5
ROWS=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_catalog_rows' LIMIT 1" 2>/dev/null)

echo "Current values found:"
echo "  Display Mode: '$DISPLAY_MODE'"
echo "  Order By: '$ORDER_BY'"
echo "  Columns: '$COLUMNS'"
echo "  Rows: '$ROWS'"

# Get initial values for comparison (anti-gaming: did they actually change it?)
INITIAL_COLS=$(cat /tmp/initial_columns.txt 2>/dev/null || echo "4")
INITIAL_ROWS=$(cat /tmp/initial_rows.txt 2>/dev/null || echo "4")

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/customizer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "current_config": {
        "display_mode": "$DISPLAY_MODE",
        "orderby": "$ORDER_BY",
        "columns": "$COLUMNS",
        "rows": "$ROWS"
    },
    "initial_config": {
        "columns": "$INITIAL_COLS",
        "rows": "$INITIAL_ROWS"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="