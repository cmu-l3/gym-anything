#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export Event Rules from API
echo "Exporting Event Rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")
echo "$RULES_JSON" > /tmp/event_rules.json

# Export Camera List (to verify camera IDs)
echo "Exporting Camera List..."
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")
echo "$DEVICES_JSON" > /tmp/devices.json

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "timestamp": $(date +%s),
    "event_rules_path": "/tmp/event_rules.json",
    "devices_path": "/tmp/devices.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete."