#!/bin/bash
echo "=== Exporting Create Order Report View Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if the view exists in config
VIEW_EXISTS="false"
VIEW_CONFIG_JSON="{}"

# Try to get the view configuration as JSON using Drush
# We use 'views.view.order_report' because the machine name is derived from "Order Report"
if drush_cmd config:get views.view.order_report > /dev/null 2>&1; then
    VIEW_EXISTS="true"
    # Export specific keys to JSON
    # We export the raw YAML converted to JSON for the verifier to parse
    # Drush can output JSON directly with --format=json
    VIEW_CONFIG_JSON=$(drush_cmd config:get views.view.order_report --format=json 2>/dev/null)
else
    # Fallback: check if they named it something else but with the right path
    # This is harder to query via config:get directly, but we can search the router
    # However, strictly speaking, the task implies a specific name.
    # We will stick to checking 'views.view.order_report' primarily.
    # If they named it "Commerce Order Report" (commerce_order_report), check that too.
    if drush_cmd config:get views.view.commerce_order_report > /dev/null 2>&1; then
        VIEW_EXISTS="true"
        VIEW_CONFIG_JSON=$(drush_cmd config:get views.view.commerce_order_report --format=json 2>/dev/null)
    fi
fi

# Check if the path is registered in the router (requires view to be enabled)
PATH_REGISTERED="false"
PATH_CHECK=$(drupal_db_query "SELECT name FROM router WHERE path = '/admin/commerce/order-report'" 2>/dev/null)
if [ -n "$PATH_CHECK" ]; then
    PATH_REGISTERED="true"
fi

# Verify the page returns 200 OK (access check)
# We use Drush uli to get a login link, then curl it with cookie jar to simulate admin access
# Or simpler: curl localhost/admin/commerce/order-report doesn't work easily without auth.
# We'll rely on the config check + router check for verification.

# Save result to JSON
# We need to escape the VIEW_CONFIG_JSON properly if we embed it, or save it to a separate file.
# To keep it simple for the verifier, we'll save the raw config in a separate file if it exists.

if [ "$VIEW_EXISTS" = "true" ]; then
    echo "$VIEW_CONFIG_JSON" > /tmp/view_config.json
fi

# Create main result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "view_exists": $VIEW_EXISTS,
    "path_registered": $PATH_REGISTERED,
    "config_file_path": "/tmp/view_config.json"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
if [ -f /tmp/view_config.json ]; then
    chmod 666 /tmp/view_config.json 2>/dev/null || true
fi

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="