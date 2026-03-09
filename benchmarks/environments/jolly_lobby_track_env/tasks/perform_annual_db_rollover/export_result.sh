#!/bin/bash
echo "=== Exporting Perform Annual Database Rollover Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/perform_annual_db_rollover_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check for Backup File
# We look for files matching the pattern in Documents
BACKUP_EXISTS="false"
BACKUP_PATH=""
BACKUP_SIZE="0"
BACKUP_MTIME="0"

# Find any file starting with VisitorLog_2025_Archive
FOUND_BACKUP=$(find /home/ga/Documents -name "VisitorLog_2025_Archive*" -type f | head -n 1)

if [ -n "$FOUND_BACKUP" ]; then
    BACKUP_EXISTS="true"
    BACKUP_PATH="$FOUND_BACKUP"
    BACKUP_SIZE=$(stat -c %s "$FOUND_BACKUP" 2>/dev/null || echo "0")
    BACKUP_MTIME=$(stat -c %Y "$FOUND_BACKUP" 2>/dev/null || echo "0")
fi

# 2. Check for Verification Export (Empty Log)
EXPORT_EXISTS="false"
EXPORT_PATH="/home/ga/Documents/verification_empty_log.csv"
EXPORT_SIZE="0"
EXPORT_LINE_COUNT="0"
EXPORT_MTIME="0"

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    # Count lines to see if it's empty (should be just header or 0)
    EXPORT_LINE_COUNT=$(wc -l < "$EXPORT_PATH" 2>/dev/null || echo "0")
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
    "app_running": $APP_RUNNING,
    "backup": {
        "exists": $BACKUP_EXISTS,
        "path": "$BACKUP_PATH",
        "size_bytes": $BACKUP_SIZE,
        "mtime": $BACKUP_MTIME
    },
    "export": {
        "exists": $EXPORT_EXISTS,
        "path": "$EXPORT_PATH",
        "size_bytes": $EXPORT_SIZE,
        "line_count": $EXPORT_LINE_COUNT,
        "mtime": $EXPORT_MTIME
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="