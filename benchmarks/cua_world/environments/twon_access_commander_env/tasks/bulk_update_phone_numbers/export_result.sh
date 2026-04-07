#!/bin/bash
echo "=== Exporting bulk_update_phone_numbers task result ==="

source /workspace/scripts/task_utils.sh

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot as evidence
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png

# Re-authenticate to ensure a valid session
ac_login

# Fetch the final state of all users
echo "Fetching final user records..."
ac_api GET "/users" > /tmp/final_users.json 2>/dev/null

# Create a summary result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_users_file": "/tmp/initial_users.json",
    "final_users_file": "/tmp/final_users.json",
    "final_screenshot": "/tmp/task_final_state.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json