#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Export System State (Devices Configuration)
# This is the ground truth for programmatic verification
echo "Exporting camera configurations..."
refresh_nx_token > /dev/null 2>&1 || true
nx_api_get "/rest/v1/devices" > /tmp/final_devices_config.json

# 3. Check Report File
REPORT_PATH="/home/ga/recording_policy_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (base64 encode to safely put in JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png",
    "devices_config_path": "/tmp/final_devices_config.json"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/final_devices_config.json

echo "=== Export complete ==="