#!/bin/bash
# export_result.sh - Post-task hook for bookmark_library_export
set -e

echo "=== Exporting Bookmark Library Task Results ==="

# 1. Kill Edge to force flush of Bookmarks JSON to disk
# (Edge holds bookmarks in memory and writes periodically or on exit)
echo "Closing Edge to flush bookmarks..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 2. Capture verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File paths
EXPORT_FILE="/home/ga/Desktop/district_bookmarks.html"
INSTRUCTIONS_FILE="/home/ga/Desktop/bookmark_instructions.txt"
BOOKMARKS_DB="/home/ga/.config/microsoft-edge/Default/Bookmarks"

# Check output files existence and modification times
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

EXPORT_STATUS=$(check_file "$EXPORT_FILE")
INSTRUCTIONS_STATUS=$(check_file "$INSTRUCTIONS_FILE")
BOOKMARKS_DB_EXISTS=$([ -f "$BOOKMARKS_DB" ] && echo "true" || echo "false")

# 3. Take final screenshot (of desktop or closed state, useful for VLM context)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bookmarks_db_exists": $BOOKMARKS_DB_EXISTS,
    "export_file_status": $EXPORT_STATUS,
    "instructions_file_status": $INSTRUCTIONS_STATUS,
    "bookmarks_db_path": "$BOOKMARKS_DB",
    "export_file_path": "$EXPORT_FILE",
    "instructions_file_path": "$INSTRUCTIONS_FILE"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="