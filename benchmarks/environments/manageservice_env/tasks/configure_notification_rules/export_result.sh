#!/bin/bash
# Export results for "configure_notification_rules" task
echo "=== Exporting Configure Notification Rules results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Capture Final Screenshot (System level)
take_screenshot /tmp/task_final_system_screenshot.png

# 2. Check for Agent's Screenshot
AGENT_SCREENSHOT_EXISTS="false"
if [ -f "/tmp/notification_rules_final.png" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    # Check if modified after task start
    FILE_TIME=$(stat -c %Y /tmp/notification_rules_final.png 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START_TIME" ]; then
        AGENT_SCREENSHOT_VALID="true"
    else
        AGENT_SCREENSHOT_VALID="false"
    fi
else
    AGENT_SCREENSHOT_VALID="false"
fi

# 3. Dump Final Database State
# We export the table again to compare in the verifier
echo "Exporting final database state..."
FINAL_DB_DUMP="/tmp/final_notification_rules.txt"
# Try multiple table variations to be safe
sdp_db_exec "SELECT * FROM NotificationRule;" > "$FINAL_DB_DUMP" 2>/dev/null || \
sdp_db_exec "SELECT * FROM notification_rules;" > "$FINAL_DB_DUMP" 2>/dev/null || \
echo "Could not dump notification rules" > "$FINAL_DB_DUMP"

# Also try to get specific columns if possible for easier parsing, but raw dump is safer for unknown schema versions
# We will use Python in the verifier to parse the raw text dump if needed, 
# or we can try to format it as JSON here if we knew the columns.
# Let's try to get a structured dump using psql aligned output if possible, but keep it simple.

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $CURRENT_TIME,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $AGENT_SCREENSHOT_VALID,
    "agent_screenshot_path": "/tmp/notification_rules_final.png",
    "system_screenshot_path": "/tmp/task_final_system_screenshot.png"
}
EOF

# Save JSON result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

# Save DB dumps to readable location for verifier
cp /tmp/initial_notification_rules.txt /tmp/db_initial.txt 2>/dev/null || true
cp /tmp/final_notification_rules.txt /tmp/db_final.txt 2>/dev/null || true
chmod 666 /tmp/db_initial.txt /tmp/db_final.txt 2>/dev/null || true

echo "=== Export Complete ==="