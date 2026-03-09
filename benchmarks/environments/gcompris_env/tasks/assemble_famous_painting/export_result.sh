#!/bin/bash
echo "=== Exporting assemble_famous_painting results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final system state (backup to agent's screenshot)
take_screenshot /tmp/task_final.png

# Paths expected from agent
AGENT_SCREENSHOT="/home/ga/Documents/painting_solved.png"
AGENT_TEXT="/home/ga/Documents/painting_info.txt"

# Check Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING="false"
if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    MTIME=$(stat -c %Y "$AGENT_SCREENSHOT")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING="true"
    fi
fi

# Check Text File
TEXT_EXISTS="false"
TEXT_CREATED_DURING="false"
TEXT_CONTENT=""
if [ -f "$AGENT_TEXT" ]; then
    TEXT_EXISTS="true"
    MTIME=$(stat -c %Y "$AGENT_TEXT")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING="true"
    fi
    # Read content (limit length for safety)
    TEXT_CONTENT=$(head -n 1 "$AGENT_TEXT")
fi

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid_time": $SCREENSHOT_CREATED_DURING,
    "text_file_exists": $TEXT_EXISTS,
    "text_valid_time": $TEXT_CREATED_DURING,
    "text_content": "$(echo "$TEXT_CONTENT" | sed 's/"/\\"/g')",
    "agent_screenshot_path": "$AGENT_SCREENSHOT",
    "final_state_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json