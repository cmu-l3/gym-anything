#!/bin/bash
echo "=== Exporting clear_watchlist_visitor result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/clear_watchlist_visitor_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null 2>&1 || pgrep -f "Lobby" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# Create result JSON
# We rely on VLM verification for the actual logic, but we export basic telemetry
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="