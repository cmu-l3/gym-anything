#!/bin/bash
echo "=== Exporting set_watchlist_expiration result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database Modification
# Find the likely database file
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack*.mdb" -o -name "Lobby.mdb" 2>/dev/null | head -1)
DB_MODIFIED="false"
DB_SIZE="0"

if [ -f "$DB_FILE" ]; then
    TASK_START=$(cat /tmp/set_watchlist_expiration_start_time 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    DB_SIZE=$(stat -c %s "$DB_FILE" 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Copy DB for analysis (if needed by verifier, though we rely mostly on VLM)
    cp "$DB_FILE" /tmp/final_db.mdb
fi

# 3. Check if Lobby Track is still running
APP_RUNNING="false"
if pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "db_found": $([ -f "$DB_FILE" ] && echo "true" || echo "false"),
    "db_modified": $DB_MODIFIED,
    "db_size": $DB_SIZE,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date +%s)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="