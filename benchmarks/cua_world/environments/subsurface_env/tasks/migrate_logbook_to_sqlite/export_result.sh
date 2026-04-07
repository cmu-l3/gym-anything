#!/bin/bash
set -e
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DB_PATH="/home/ga/Documents/dives.db"
SSRF_PATH="/home/ga/Documents/dives.ssrf"

# Check DB File
DB_EXISTS="false"
DB_SIZE="0"
DB_MTIME="0"
DB_CREATED_DURING_TASK="false"

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -ge "$TASK_START" ]; then
        DB_CREATED_DURING_TASK="true"
    fi
fi

# Check SSRF File
SSRF_EXISTS="false"
SSRF_SIZE="0"

if [ -f "$SSRF_PATH" ]; then
    SSRF_EXISTS="true"
    SSRF_SIZE=$(stat -c %s "$SSRF_PATH" 2>/dev/null || echo "0")
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": $DB_EXISTS,
    "db_size_bytes": $DB_SIZE,
    "db_created_during_task": $DB_CREATED_DURING_TASK,
    "ssrf_exists": $SSRF_EXISTS,
    "ssrf_size_bytes": $SSRF_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="