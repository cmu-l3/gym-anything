#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Consolidate Host Records Result ==="

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/consolidate_host_records_start_time 2>/dev/null || echo "0")

# Capture Final Screenshot (System)
take_screenshot /tmp/task_final.png

# Check if agent's proof screenshot exists
AGENT_SCREENSHOT="/home/ga/consolidated_host_result.png"
SCREENSHOT_EXISTS="false"
if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Ensure the verifier can read it
    cp "$AGENT_SCREENSHOT" /tmp/agent_proof.png
fi

# Check Database Modification
DB_MODIFIED="false"
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" | head -1)
if [ -n "$DB_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$DB_FILE")
    INITIAL_MTIME=$(cat /tmp/initial_db_mtime 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        DB_MODIFIED="true"
    fi
fi

# Check if Lobby Track is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/agent_proof.png",
    "db_modified": $DB_MODIFIED,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"