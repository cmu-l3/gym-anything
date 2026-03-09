#!/bin/bash
echo "=== Exporting restore_visitor_database result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
DB_PATH=$(cat /tmp/active_db_path.txt 2>/dev/null)
BACKUP_PATH="/home/ga/.wine/drive_c/LobbyTrackBackup/LobbyTrackDB_backup.mdb"
CONFIRMATION_PATH="/home/ga/.wine/drive_c/LobbyTrackBackup/restore_confirmation.txt"
EMPTY_SIZE=$(cat /tmp/empty_db_size.txt 2>/dev/null || echo "0")
BACKUP_SIZE=$(cat /tmp/backup_db_size.txt 2>/dev/null || echo "0")

# 1. Check Active Database Status
DB_EXISTS="false"
DB_SIZE="0"
DB_MTIME="0"
DB_RESTORED="false"

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c%s "$DB_PATH")
    DB_MTIME=$(stat -c%Y "$DB_PATH")
    
    # Check if size is closer to backup size than empty size
    # Allow 20% tolerance or exact match
    SIZE_DIFF_BACKUP=$(( DB_SIZE - BACKUP_SIZE ))
    SIZE_DIFF_BACKUP=${SIZE_DIFF_BACKUP#-} # abs
    
    # Logic: If current size is significantly larger than empty size AND close to backup size
    if [ "$DB_SIZE" -gt "$((EMPTY_SIZE + 10000))" ]; then
        DB_RESTORED="true"
    elif [ "$SIZE_DIFF_BACKUP" -lt 50000 ]; then
        DB_RESTORED="true"
    fi
fi

# 2. Check Confirmation File
CONFIRM_EXISTS="false"
CONFIRM_CONTENT=""
if [ -f "$CONFIRMATION_PATH" ]; then
    CONFIRM_EXISTS="true"
    CONFIRM_CONTENT=$(head -n 1 "$CONFIRMATION_PATH")
fi

# 3. Check App Status
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": $DB_EXISTS,
    "db_size": $DB_SIZE,
    "db_mtime": $DB_MTIME,
    "backup_size": $BACKUP_SIZE,
    "empty_db_size": $EMPTY_SIZE,
    "db_restored_heuristic": $DB_RESTORED,
    "confirmation_exists": $CONFIRM_EXISTS,
    "confirmation_content": "$(echo "$CONFIRM_CONTENT" | sed 's/"/\\"/g')",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="