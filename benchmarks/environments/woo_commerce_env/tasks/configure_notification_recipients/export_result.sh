#!/bin/bash
# Export script for Configure Notification Recipients task

echo "=== Exporting Configure Notification Recipients Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve current email settings via WP-CLI
cd /var/www/html/wordpress

# Helper to get recipient from option array safely
get_recipient() {
    local option_name="$1"
    # WP-CLI returns JSON for array options
    wp option get "$option_name" --format=json --allow-root 2>/dev/null | jq -r '.recipient // empty'
}

CURRENT_NEW_ORDER=$(get_recipient "woocommerce_new_order_settings")
CURRENT_CANCELLED=$(get_recipient "woocommerce_cancelled_order_settings")
CURRENT_FAILED=$(get_recipient "woocommerce_failed_order_settings")

# Retrieve initial state
INITIAL_NEW_ORDER=$(cat /tmp/initial_state.json | jq -r '.new_order')
INITIAL_CANCELLED=$(cat /tmp/initial_state.json | jq -r '.cancelled_order')
INITIAL_FAILED=$(cat /tmp/initial_state.json | jq -r '.failed_order')

# Determine if changes occurred
CHANGED_NEW="false"
CHANGED_CANCELLED="false"
CHANGED_FAILED="false"

[ "$CURRENT_NEW_ORDER" != "$INITIAL_NEW_ORDER" ] && CHANGED_NEW="true"
[ "$CURRENT_CANCELLED" != "$INITIAL_CANCELLED" ] && CHANGED_CANCELLED="true"
[ "$CURRENT_FAILED" != "$INITIAL_FAILED" ] && CHANGED_FAILED="true"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "new_order_recipient": "$(json_escape "$CURRENT_NEW_ORDER")",
    "cancelled_order_recipient": "$(json_escape "$CURRENT_CANCELLED")",
    "failed_order_recipient": "$(json_escape "$CURRENT_FAILED")",
    "initial_new_order": "$(json_escape "$INITIAL_NEW_ORDER")",
    "changed_new": $CHANGED_NEW,
    "changed_cancelled": $CHANGED_CANCELLED,
    "changed_failed": $CHANGED_FAILED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="