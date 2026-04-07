#!/bin/bash
set -euo pipefail
echo "=== Exporting create_custom_fields task result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_custom_field_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Fetch final state of custom fields via API
API_KEY=$(redmine_admin_api_key)
# We fetch XML or JSON. JSON is easier to parse in Python.
# Note: The standard Redmine API /custom_fields.json lists fields. 
# It includes: id, name, customized_type, field_format, regexp, min_length, max_length, is_required, is_filter, search_by_custom_field, default_value, possible_values, visible, trackers, roles.
CUSTOM_FIELDS_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/custom_fields.json")

# Create a temporary JSON file for the result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Construct the result JSON
# We embed the raw API response so the python verifier can parse it robustly
jq -n \
  --argjson start_time "$TASK_START" \
  --argjson end_time "$TASK_END" \
  --argjson initial_count "$INITIAL_COUNT" \
  --arg app_running "$APP_RUNNING" \
  --argjson api_response "$CUSTOM_FIELDS_JSON" \
  '{
    task_start: $start_time,
    task_end: $end_time,
    initial_cf_count: $initial_count,
    app_was_running: ($app_running == "true"),
    custom_fields_data: $api_response,
    screenshot_path: "/tmp/task_final.png"
  }' > "$TEMP_JSON"

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="