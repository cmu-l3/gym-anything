#!/bin/bash
# Export script for Customize Checkout Flow task
echo "=== Exporting Customize Checkout Flow Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Export the final configuration using Drush
echo "Exporting checkout flow configuration..."
cd /var/www/html/drupal
# We capture the full JSON output of the config object
CONFIG_JSON=$(vendor/bin/drush config:get commerce_checkout.commerce_checkout_flow.default --format=json 2>/dev/null)

# 2. Check for configuration changes (Anti-gaming)
CURRENT_CONFIG_HASH=$(echo "$CONFIG_JSON" | md5sum | awk '{print $1}')
INITIAL_CONFIG_HASH=$(cat /tmp/initial_config_hash.txt 2>/dev/null || echo "")

CONFIG_CHANGED="false"
if [ "$CURRENT_CONFIG_HASH" != "$INITIAL_CONFIG_HASH" ]; then
    CONFIG_CHANGED="true"
fi

# 3. Check if we can find the Completion Message in the database directly as a backup
# (Sometimes complex nested JSON parsing in bash is fragile)
DB_MESSAGE_CHECK=$(drupal_db_query "SELECT data FROM config WHERE name = 'commerce_checkout.commerce_checkout_flow.default'" | grep -o "Thank you for shopping at Urban Electronics" || echo "")
DB_MESSAGE_FOUND="false"
if [ -n "$DB_MESSAGE_CHECK" ]; then
    DB_MESSAGE_FOUND="true"
fi

# 4. Construct the result JSON
# We embed the Drush JSON output directly into our result object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_changed": $CONFIG_CHANGED,
    "db_message_found": $DB_MESSAGE_FOUND,
    "screenshot_path": "/tmp/task_final.png",
    "final_configuration": ${CONFIG_JSON:-{}}
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="