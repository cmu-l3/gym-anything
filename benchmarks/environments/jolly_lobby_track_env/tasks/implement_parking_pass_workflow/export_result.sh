#!/bin/bash
echo "=== Exporting Parking Pass Workflow Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Search for the created Badge Template file
echo "Searching for Badge Template file..."
# Look for files matching "Parking Permit" created after task start
TEMPLATE_PATH=$(find /home/ga/.wine/drive_c -name "Parking Permit*" -not -path "*/Recent/*" -newermt "@$TASK_START" 2>/dev/null | head -1)

TEMPLATE_FOUND="false"
TEMPLATE_CONTENT_MATCH="false"
STATIC_TEXT_MATCH="false"
TEMPLATE_SIZE="0"

if [ -n "$TEMPLATE_PATH" ]; then
    echo "Found template: $TEMPLATE_PATH"
    TEMPLATE_FOUND="true"
    TEMPLATE_SIZE=$(stat -c %s "$TEMPLATE_PATH" 2>/dev/null || echo "0")
    
    # Check content for "License Plate" (field binding) and "PARKING PERMIT" (static text)
    # Use strings/grep because it might be binary
    if strings "$TEMPLATE_PATH" | grep -iq "License Plate"; then
        TEMPLATE_CONTENT_MATCH="true"
    fi
    if strings "$TEMPLATE_PATH" | grep -q "PARKING PERMIT"; then
        STATIC_TEXT_MATCH="true"
    fi
    
    # Copy for verification
    cp "$TEMPLATE_PATH" /tmp/agent_template_file 2>/dev/null || true
fi

# 2. Check for Database Schema modification ("License Plate" field)
echo "Checking for 'License Plate' field in database/config..."
FIELD_FOUND="false"

# Search all modified files in Wine prefix for the string "License Plate"
# This covers .sdf (SQL CE), .xml (Config), .ini, etc.
# Limit to files modified during task
MODIFIED_FILES=$(find /home/ga/.wine/drive_c -type f -newermt "@$TASK_START" -not -path "*/temp/*" -not -path "*/log/*" 2>/dev/null)

for f in $MODIFIED_FILES; do
    # Skip the template file itself, we want the DB/Schema definition
    if [ "$f" == "$TEMPLATE_PATH" ]; then continue; fi
    
    # Grep binary safe
    if strings "$f" | grep -iq "License Plate"; then
        echo "Found 'License Plate' string in modified file: $f"
        FIELD_FOUND="true"
        break
    fi
done

# 3. Check if App is running
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
    "template_found": $TEMPLATE_FOUND,
    "template_path": "$TEMPLATE_PATH",
    "template_size_bytes": $TEMPLATE_SIZE,
    "template_has_field_link": $TEMPLATE_CONTENT_MATCH,
    "template_has_static_text": $STATIC_TEXT_MATCH,
    "field_added_to_schema": $FIELD_FOUND,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="