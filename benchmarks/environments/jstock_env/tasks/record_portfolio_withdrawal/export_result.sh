#!/bin/bash
echo "=== Exporting task results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Task Execution Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 3. Analyze Target File (depositsummary.csv)
TARGET_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/depositsummary.csv"
FILE_EXISTS="false"
FILE_MODIFIED="false"
CSV_CONTENT=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read content (base64 encode to safely transport via JSON)
    # We only care about lines after the header
    CSV_CONTENT=$(base64 -w 0 "$TARGET_FILE")
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "target_file_exists": $FILE_EXISTS,
    "target_file_modified": $FILE_MODIFIED,
    "target_file_content_b64": "$CSV_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="