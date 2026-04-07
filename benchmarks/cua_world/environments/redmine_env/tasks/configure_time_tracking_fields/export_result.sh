#!/bin/bash
echo "=== Exporting configure_time_tracking_fields results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Admin API Key from seed result to query API
API_KEY=$(redmine_admin_api_key)

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo "ERROR: Could not retrieve Admin API Key"
  API_KEY="admin" # Fallback, unlikely to work if key generated dynamically
fi

# Export Custom Fields
echo "Exporting Custom Fields..."
curl -s -H "X-Redmine-API-Key: $API_KEY" \
     "$REDMINE_BASE_URL/custom_fields.json" \
     > /tmp/custom_fields_export.json

# Export Time Entries (include custom fields in response)
echo "Exporting Time Entries..."
# Note: Redmine API returns recent entries by default. 
# We fetch entries created by current user (admin/me) or all.
curl -s -H "X-Redmine-API-Key: $API_KEY" \
     "$REDMINE_BASE_URL/time_entries.json?include=custom_fields&limit=10&sort=created_on:desc" \
     > /tmp/time_entries_export.json

# Prepare final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "custom_fields": $(cat /tmp/custom_fields_export.json 2>/dev/null || echo "{}"),
    "time_entries": $(cat /tmp/time_entries_export.json 2>/dev/null || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="