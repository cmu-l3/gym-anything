#!/bin/bash
echo "=== Exporting Upload Student Document Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Search for the uploaded file on the server
# We search broadly in the web root because OpenSIS versions vary in storage paths
SEARCH_ROOT="/var/www/html/opensis"
TARGET_FILENAME="transcript_source.pdf"

echo "Searching for $TARGET_FILENAME in $SEARCH_ROOT..."
FOUND_FILES=$(find "$SEARCH_ROOT" -type f -name "*transcript_source*.pdf" 2>/dev/null)

FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE="0"
FILE_TIMESTAMP="0"
IS_NEW_FILE="false"

# Check each found file
for f in $FOUND_FILES; do
    echo "Checking candidate: $f"
    f_mtime=$(stat -c %Y "$f")
    f_size=$(stat -c %s "$f")
    
    # Check if modified AFTER task start (Anti-gaming)
    if [ "$f_mtime" -gt "$TASK_START" ]; then
        # Check if size matches roughly (our dummy PDF is small)
        if [ "$f_size" -gt 0 ]; then
            FILE_FOUND="true"
            FILE_PATH="$f"
            FILE_SIZE="$f_size"
            FILE_TIMESTAMP="$f_mtime"
            IS_NEW_FILE="true"
            echo "MATCH: Found valid uploaded file at $f"
            break
        fi
    fi
done

# 3. Check if Chrome is still running
APP_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_found": $FILE_FOUND,
    "found_file_path": "$FILE_PATH",
    "found_file_size": $FILE_SIZE,
    "found_file_timestamp": $FILE_TIMESTAMP,
    "is_new_file": $IS_NEW_FILE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="