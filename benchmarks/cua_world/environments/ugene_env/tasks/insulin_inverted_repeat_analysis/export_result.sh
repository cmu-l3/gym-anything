#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

GFF_PATH="/home/ga/UGENE_Data/repeat_analysis/inverted_repeats.gff"
TXT_PATH="/home/ga/UGENE_Data/repeat_analysis/summary.txt"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check GFF output
GFF_EXISTS="false"
GFF_CREATED_DURING_TASK="false"
GFF_SIZE="0"

if [ -f "$GFF_PATH" ]; then
    GFF_EXISTS="true"
    GFF_SIZE=$(stat -c %s "$GFF_PATH" 2>/dev/null || echo "0")
    GFF_MTIME=$(stat -c %Y "$GFF_PATH" 2>/dev/null || echo "0")
    
    if [ "$GFF_MTIME" -gt "$TASK_START" ]; then
        GFF_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check TXT output
TXT_EXISTS="false"
TXT_CREATED_DURING_TASK="false"
TXT_SIZE="0"

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c %s "$TXT_PATH" 2>/dev/null || echo "0")
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Verify UGENE was running
APP_RUNNING=$(pgrep -f "ugene\|UGENE" > /dev/null && echo "true" || echo "false")

# 5. Create JSON result using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "gff": {
        "exists": $GFF_EXISTS,
        "created_during_task": $GFF_CREATED_DURING_TASK,
        "size_bytes": $GFF_SIZE,
        "path": "$GFF_PATH"
    },
    "summary": {
        "exists": $TXT_EXISTS,
        "created_during_task": $TXT_CREATED_DURING_TASK,
        "size_bytes": $TXT_SIZE,
        "path": "$TXT_PATH"
    }
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="