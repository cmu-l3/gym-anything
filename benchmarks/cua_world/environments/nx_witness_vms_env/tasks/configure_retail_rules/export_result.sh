#!/bin/bash
echo "=== Exporting configure_retail_rules results ==="

source /workspace/scripts/task_utils.sh

# 1. Record basic task metrics
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Export Event Rules from API
# This is the PRIMARY evidence for verification.
# We verify against the actual system state, not just pixels.
echo "Exporting Event Rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Save rules to a temporary file
echo "$RULES_JSON" > /tmp/event_rules_export.json

# 4. Export Camera List (to verify targeting)
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")
echo "$DEVICES_JSON" > /tmp/devices_export.json

# 5. Check if Desktop Client is still running
APP_RUNNING=$(pgrep -f "client.*networkoptix" > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "event_rules_file": "/tmp/event_rules_export.json",
    "devices_file": "/tmp/devices_export.json"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="