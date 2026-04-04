#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/export_visitor_log_start_time 2>/dev/null || echo "0")

# Directories
DESKTOP_DIR="/home/ga/Desktop"

# 1. Search for the exported file (handling various extensions)
FOUND_FILE=""
FOUND_EXT=""
FILE_SIZE="0"
FILE_MTIME="0"

# Priority to CSV, but accept others
for ext in csv txt xls xlsx xml html; do
    if [ -f "$DESKTOP_DIR/visitor_audit_export.$ext" ]; then
        FOUND_FILE="$DESKTOP_DIR/visitor_audit_export.$ext"
        FOUND_EXT="$ext"
        break
    fi
done

# 2. Gather file metrics if found
FILE_CREATED_DURING_TASK="false"
HEADER_DETECTED="false"
RECORD_COUNT="0"
NAMES_FOUND_COUNT="0"
FOUND_NAMES_LIST=""

if [ -n "$FOUND_FILE" ]; then
    echo "Found export file: $FOUND_FILE"
    
    # Size
    FILE_SIZE=$(stat -c %s "$FOUND_FILE" 2>/dev/null || echo "0")
    
    # Timestamp check (Anti-gaming)
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Content Analysis (Simple grep/counting)
    # Check for header-like terms
    if grep -Eiq "Name|First|Last|Company|Time|Date|Host" "$FOUND_FILE"; then
        HEADER_DETECTED="true"
    fi

    # Count lines (approximate record count)
    RECORD_COUNT=$(wc -l < "$FOUND_FILE")
    
    # Check for specific names (Gonzalez, O'Brien, Sharma, Weber, Zhang, Hassan)
    # We use a loop to check each required name
    NAMES_TO_CHECK=("Gonzalez" "O'Brien" "Sharma" "Weber" "Zhang" "Hassan")
    
    for name in "${NAMES_TO_CHECK[@]}"; do
        if grep -Fq "$name" "$FOUND_FILE"; then
            NAMES_FOUND_COUNT=$((NAMES_FOUND_COUNT + 1))
            FOUND_NAMES_LIST="${FOUND_NAMES_LIST}${name},"
        fi
    done
else
    echo "No matching export file found on Desktop."
fi

# 3. Check if App is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_found": $( [ -n "$FOUND_FILE" ] && echo "true" || echo "false" ),
    "file_path": "$FOUND_FILE",
    "file_extension": "$FOUND_EXT",
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "header_detected": $HEADER_DETECTED,
    "line_count": $RECORD_COUNT,
    "names_found_count": $NAMES_FOUND_COUNT,
    "found_names_list": "${FOUND_NAMES_LIST%,}",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result data saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="