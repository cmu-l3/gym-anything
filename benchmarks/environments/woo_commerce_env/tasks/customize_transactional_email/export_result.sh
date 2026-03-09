#!/bin/bash
# Export script for Customize Transactional Email task

echo "=== Exporting Customize Transactional Email Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch the current settings for the completed order email
# We use WP-CLI to get it as JSON, which handles the PHP unserialization for us
echo "Fetching current email settings..."
CURRENT_SETTINGS_JSON=$(wp option get woocommerce_customer_completed_order_settings --format=json --allow-root 2>/dev/null || echo "{}")

# Get initial settings for comparison (to detect changes)
INITIAL_SETTINGS_JSON=$(cat /tmp/initial_email_settings.json 2>/dev/null || echo "{}")

# Create a temporary JSON file combining everything
TEMP_JSON=$(mktemp /tmp/email_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "current_settings": $CURRENT_SETTINGS_JSON,
    "initial_settings": $INITIAL_SETTINGS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="