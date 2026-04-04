#!/bin/bash
# Export script for Enforce Checkout Registration task
echo "=== Exporting enforce_checkout_registration Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

DRUSH="/var/www/html/drupal/vendor/bin/drush"
DRUPAL_ROOT="/var/www/html/drupal"

# Export the full configuration object for the default checkout flow
echo "Exporting commerce_checkout_flow.default configuration..."
cd "$DRUPAL_ROOT"

# Use Drush to get the config in JSON format
# This captures the actual state of the system
FINAL_CONFIG=$($DRUSH config:get commerce_checkout_flow.default --format=json 2>/dev/null)

# Save to a temp file first
TEMP_JSON=$(mktemp /tmp/checkout_flow_result.XXXXXX.json)
echo "$FINAL_CONFIG" > "$TEMP_JSON"

# Create a wrapper JSON that includes metadata and the config
# This ensures we have a valid JSON object even if Drush output is weird
WRAPPER_JSON=$(mktemp /tmp/task_result.XXXXXX.json)

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create the final result structure
# We embed the drush output inside a 'config' key
cat > "$WRAPPER_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drush_export_success": $(if [ -n "$FINAL_CONFIG" ]; then echo "true"; else echo "false"; fi),
    "config_dump": $TEMP_JSON
}
EOF

# Note: We can't easily embed the content of TEMP_JSON into WRAPPER_JSON using bash safely due to escaping.
# Instead, we'll let python (verifier) read the drush output directly, or just save the drush output as the result.
# Actually, the simplest way is to just save the Drush JSON output as the result file, 
# and verify specific keys in Python.

# Let's save the Drush output directly as the primary result file.
# If Drush failed, write a failure JSON.
if [ -z "$FINAL_CONFIG" ]; then
    echo '{"error": "Failed to export config"}' > /tmp/task_result.json
else
    echo "$FINAL_CONFIG" > /tmp/task_result.json
fi

# Make readable
chmod 666 /tmp/task_result.json

echo "Configuration exported to /tmp/task_result.json"
echo "=== Export Complete ==="