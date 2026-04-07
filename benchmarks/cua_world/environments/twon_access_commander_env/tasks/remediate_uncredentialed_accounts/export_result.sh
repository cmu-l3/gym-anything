#!/bin/bash
echo "=== Exporting remediate_uncredentialed_accounts task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Fetch all users via API to check their states
ac_login
USERS_JSON=$(ac_api GET "/users" 2>/dev/null)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "users_data": $USERS_JSON,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Safely move to final location
rm -f /tmp/remediation_result.json 2>/dev/null || sudo rm -f /tmp/remediation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/remediation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/remediation_result.json
chmod 666 /tmp/remediation_result.json 2>/dev/null || sudo chmod 666 /tmp/remediation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/remediation_result.json"
echo "=== Export complete ==="