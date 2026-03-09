#!/bin/bash
echo "=== Exporting Configure Self-Service Portal Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Visual Proof)
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Final Settings
# We fetch the configuration parameters from GlobalConfig table
echo "Querying database for final settings..."

# Extract key parameters. We use a JSON construction approach.
# paramvalue is usually 'true'/'false' for booleans in SDP.

REOPEN_VAL=$(sdp_db_exec "SELECT paramvalue FROM GlobalConfig WHERE parameter='REOPEN_RESOLVED_REQUEST'")
COST_VAL=$(sdp_db_exec "SELECT paramvalue FROM GlobalConfig WHERE parameter='SHOW_REQ_COST'")
WELCOME_VAL=$(sdp_db_exec "SELECT paramvalue FROM GlobalConfig WHERE parameter='WELCOME_MESSAGE'")

# Clean up newlines/whitespace
REOPEN_VAL=$(echo "$REOPEN_VAL" | tr -d '[:space:]')
COST_VAL=$(echo "$COST_VAL" | tr -d '[:space:]')
# Welcome message might contain spaces, so just trim leading/trailing
WELCOME_VAL=$(echo "$WELCOME_VAL" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# 3. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_settings": {
        "reopen_request": "$REOPEN_VAL",
        "show_cost": "$COST_VAL",
        "welcome_message": "$WELCOME_VAL"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location (handling permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="