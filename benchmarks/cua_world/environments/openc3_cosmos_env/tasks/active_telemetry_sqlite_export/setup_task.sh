#!/bin/bash
echo "=== Setting up Active Telemetry SQLite Export task ==="

source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Clean up any stale files from previous runs to prevent false positives
rm -f /home/ga/Desktop/telemetry_archive.db 2>/dev/null || true
rm -f /tmp/active_telemetry_sqlite_export_result.json 2>/dev/null || true

# Record task start timestamp (Anti-Gaming check)
date +%s > /tmp/active_telemetry_sqlite_export_start_ts
echo "Task start recorded: $(cat /tmp/active_telemetry_sqlite_export_start_ts)"

# Record initial COLLECT command count to track if the agent really sent commands
INITIAL_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT command count: $INITIAL_CMD_COUNT"
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/active_telemetry_initial_cmd_count

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30 || true

# Navigate to COSMOS Home Page
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial state screenshot
take_screenshot /tmp/active_telemetry_sqlite_export_start.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Time-series telemetry archiving to SQLite with active command injection."
echo "Output database: /home/ga/Desktop/telemetry_archive.db"
echo ""