#!/bin/bash
# Export script for Configure Shop Sidebar task

echo "=== Exporting Configure Shop Sidebar Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# ==============================================================================
# Extract Widget Configuration via WP-CLI
# ==============================================================================

# 1. Get the list of widgets in the sidebar
# This returns a JSON object where "sidebar-1" is an array of widget IDs (e.g., ["search-2", "text-5"])
SIDEBARS_WIDGETS_JSON=$(wp option get sidebars_widgets --format=json --allow-root 2>/dev/null)

# 2. Get the specific settings for the Product Categories widget
# This returns a JSON object keyed by instance ID (e.g., {"2": {"title": "", "count": 1, ...}})
# We fetch the entire option to parse later in python, as we don't know the specific instance ID yet
CATS_WIDGET_SETTINGS_JSON=$(wp option get widget_woocommerce_product_categories --format=json --allow-root 2>/dev/null || echo "{}")

# 3. Get Price Filter settings (just in case, though it has few options)
PRICE_WIDGET_SETTINGS_JSON=$(wp option get widget_woocommerce_price_filter --format=json --allow-root 2>/dev/null || echo "{}")

# 4. Get Product Search settings
SEARCH_WIDGET_SETTINGS_JSON=$(wp option get widget_woocommerce_product_search --format=json --allow-root 2>/dev/null || echo "{}")

# 5. Get Initial State (for comparison)
INITIAL_STATE=$(cat /tmp/initial_sidebars_widgets.json 2>/dev/null || echo "{}")

# Create a temporary JSON file for the result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Construct the result JSON
# We embed the raw WP-CLI outputs so the Python verifier can parse them robustly
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sidebars_widgets": $SIDEBARS_WIDGETS_JSON,
    "initial_sidebars_widgets": $INITIAL_STATE,
    "widget_settings": {
        "woocommerce_product_categories": $CATS_WIDGET_SETTINGS_JSON,
        "woocommerce_price_filter": $PRICE_WIDGET_SETTINGS_JSON,
        "woocommerce_product_search": $SEARCH_WIDGET_SETTINGS_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"