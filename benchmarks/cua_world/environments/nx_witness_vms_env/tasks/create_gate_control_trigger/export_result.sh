#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Timestamp checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Dump current Rules configuration
echo "Exporting rules..."
RULES_JSON=$(nx_api_get "/rest/v1/rules")

# 3. Dump Devices (to map Camera Name to ID)
echo "Exporting devices..."
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")

# 4. Create result JSON
# We combine rules and devices so the verifier can resolve names
cat > /tmp/task_result_data.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rules": $RULES_JSON,
    "devices": $DEVICES_JSON
}
EOF

# 5. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Save final JSON
mv /tmp/task_result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"