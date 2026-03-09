#!/bin/bash
# export_result.sh — Verify the update_account_settings task inside container

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------
# 1. Get current values from Database
# -----------------------------------------------------------------------
CURRENT_TIMEZONE=$(db_query "SELECT timezone FROM users WHERE username='admin'" | head -1 | tr -d '[:space:]')
CURRENT_EMAIL=$(db_query "SELECT email FROM users WHERE username='admin'" | head -1 | tr -d '[:space:]')

echo "Current timezone in DB: '${CURRENT_TIMEZONE}'"
echo "Current email in DB: '${CURRENT_EMAIL}'"

# -----------------------------------------------------------------------
# 2. Get initial values for comparison
# -----------------------------------------------------------------------
INITIAL_TIMEZONE="UTC"
INITIAL_EMAIL="admin@emoncms.local"

if [ -f /tmp/task_initial_state.json ]; then
    INITIAL_TIMEZONE=$(jq -r .initial_timezone /tmp/task_initial_state.json 2>/dev/null || echo "UTC")
    INITIAL_EMAIL=$(jq -r .initial_email /tmp/task_initial_state.json 2>/dev/null || echo "admin@emoncms.local")
fi

# -----------------------------------------------------------------------
# 3. Check application state
# -----------------------------------------------------------------------
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 4. Create result JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_timezone": "${INITIAL_TIMEZONE}",
    "initial_email": "${INITIAL_EMAIL}",
    "current_timezone": "${CURRENT_TIMEZONE}",
    "current_email": "${CURRENT_EMAIL}",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="