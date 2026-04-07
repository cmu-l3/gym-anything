#!/bin/bash
echo "=== Exporting record_synthetic_session result ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
RESULT_JSON="/tmp/task_result.json"

# 2. Identify NEW recording sessions
# We look for directories in Recordings/ that are NOT in the initial list
# AND were modified after task start
NEW_SESSION_DIR=""
LATEST_MTIME=0

echo "Scanning for new recordings in $RECORDINGS_DIR..."

# Iterate over all session directories
for dir in "$RECORDINGS_DIR"/OpenBCISession_*; do
    [ -d "$dir" ] || continue
    
    # Check if this dir was in the initial list
    DIRNAME=$(basename "$dir")
    if grep -qF "$DIRNAME" /tmp/initial_recordings_list.txt; then
        continue # Skip pre-existing directories
    fi
    
    # Check modification time
    DIR_MTIME=$(stat -c %Y "$dir" 2>/dev/null || echo "0")
    
    if [ "$DIR_MTIME" -gt "$TASK_START_TIME" ]; then
        echo "Found new session candidate: $DIRNAME (mtime: $DIR_MTIME)"
        # Pick the most recent one if multiple exist
        if [ "$DIR_MTIME" -gt "$LATEST_MTIME" ]; then
            LATEST_MTIME=$DIR_MTIME
            NEW_SESSION_DIR="$dir"
        fi
    fi
done

# 3. Analyze the recording file inside the new session
FILE_FOUND="false"
FILE_SIZE_BYTES=0
LINE_COUNT=0
HAS_HEADER="false"
VALID_COLUMNS="false"
FILENAME=""

if [ -n "$NEW_SESSION_DIR" ]; then
    echo "Analyzing session: $NEW_SESSION_DIR"
    
    # Find the RAW txt file (OpenBCI-RAW-*.txt)
    # Use find to locate file, sort by time to get latest
    RAW_FILE=$(find "$NEW_SESSION_DIR" -name "OpenBCI-RAW-*.txt" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$RAW_FILE" ] && [ -f "$RAW_FILE" ]; then
        FILE_FOUND="true"
        FILENAME=$(basename "$RAW_FILE")
        FILE_SIZE_BYTES=$(stat -c %s "$RAW_FILE")
        
        # Count lines (excluding comments if strictly data, but here we count total lines first)
        LINE_COUNT=$(wc -l < "$RAW_FILE")
        
        # Check for OpenBCI Header (%)
        if grep -q "^%" "$RAW_FILE" | head -1 >/dev/null; then
            HAS_HEADER="true"
        fi
        
        # Check data columns on a non-comment line (sample the last line)
        LAST_LINE=$(tail -1 "$RAW_FILE")
        # OpenBCI format: ID, ch1, ch2, ... ch8, aux1...
        # Count commas. 8 channels + ID + Aux usually means > 10 columns
        COMMA_COUNT=$(echo "$LAST_LINE" | tr -cd ',' | wc -c)
        if [ "$COMMA_COUNT" -ge 8 ]; then
            VALID_COLUMNS="true"
        fi
    fi
else
    echo "No new session directory found created after task start."
fi

# 4. Check if App is still running (it should be)
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Generate JSON Result
# Use a temp file to avoid permission issues during write
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIME,
    "session_dir_found": $( [ -n "$NEW_SESSION_DIR" ] && echo "true" || echo "false" ),
    "session_dir_path": "$NEW_SESSION_DIR",
    "raw_file_found": $FILE_FOUND,
    "raw_filename": "$FILENAME",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "total_lines": $LINE_COUNT,
    "has_valid_header": $HAS_HEADER,
    "has_valid_columns": $VALID_COLUMNS,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="