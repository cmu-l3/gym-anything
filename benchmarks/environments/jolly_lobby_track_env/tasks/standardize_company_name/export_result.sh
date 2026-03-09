#!/bin/bash
set -euo pipefail

echo "=== Exporting Standardize Company Name result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Determine App State
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null 2>&1 || pgrep -f "Lobby" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# 3. Gracefully close app to ensure DB writes are flushed
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
# Wait for flush
sleep 5

# 4. Locate and Export Database File
DB_PATH=$(cat /tmp/active_db_path.txt 2>/dev/null || echo "")
if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
    # Fallback search
    DB_PATH=$(find /home/ga -name "*.mdb" -o -name "*.sdf" | head -n 1)
fi

DB_EXISTS="false"
DB_MODIFIED="false"
DB_SIZE_BYTES="0"

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE_BYTES=$(stat -c %s "$DB_PATH")
    DB_MTIME=$(stat -c %Y "$DB_PATH")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Copy DB to temp for verifier (avoid permission issues)
    cp "$DB_PATH" /tmp/task_result_db.bin
    chmod 666 /tmp/task_result_db.bin
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_exists": $DB_EXISTS,
    "db_modified": $DB_MODIFIED,
    "db_path": "$DB_PATH",
    "db_size_bytes": $DB_SIZE_BYTES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"