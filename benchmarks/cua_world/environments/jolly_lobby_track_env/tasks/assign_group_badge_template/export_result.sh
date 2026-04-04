#!/bin/bash
echo "=== Exporting assign_group_badge_template result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/assign_group_badge_template_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check Database Modification
# We look for ANY database file modified after task start
DB_MODIFIED="false"
DB_PATH=""
DB_SIZE="0"

# Find all potential DB files
find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" -o -name "*.xml" 2>/dev/null | while read -r file; do
    MTIME=$(stat -c %Y "$file")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        # We found a modified file
        # We can't export variables from a subshell easily, so write to temp
        echo "$file" > /tmp/modified_db_path.txt
        stat -c %s "$file" > /tmp/modified_db_size.txt
        break
    fi
done

if [ -f /tmp/modified_db_path.txt ]; then
    DB_MODIFIED="true"
    DB_PATH=$(cat /tmp/modified_db_path.txt)
    DB_SIZE=$(cat /tmp/modified_db_size.txt)
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_modified": $DB_MODIFIED,
    "db_path": "$DB_PATH",
    "db_size_bytes": $DB_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="