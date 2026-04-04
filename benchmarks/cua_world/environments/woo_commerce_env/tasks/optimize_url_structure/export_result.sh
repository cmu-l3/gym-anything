#!/bin/bash
echo "=== Exporting result: optimize_url_structure ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch final permalink settings via WP-CLI
# Expected output is a JSON object like:
# {"category_base":"collection","tag_base":"labeled","attribute_base":"","product_base":"/shop/%product_cat%/"}
FINAL_SETTINGS=$(wp option get woocommerce_permalinks --format=json --allow-root --path="/var/www/html/wordpress" 2>/dev/null)
echo "Final Settings: $FINAL_SETTINGS"

# Fetch initial settings for comparison
INITIAL_SETTINGS=$(cat /tmp/initial_permalinks.json 2>/dev/null || echo "{}")

# Check if changes were made
SETTINGS_CHANGED="false"
if [ "$FINAL_SETTINGS" != "$INITIAL_SETTINGS" ]; then
    SETTINGS_CHANGED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_settings": $INITIAL_SETTINGS,
    "final_settings": $FINAL_SETTINGS,
    "settings_changed": $SETTINGS_CHANGED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="