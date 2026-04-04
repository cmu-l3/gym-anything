#!/bin/bash
echo "=== Exporting identify_software_version results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/software_inventory.txt"
GT_VERSION=$(cat /tmp/ground_truth_version.txt 2>/dev/null || echo "unknown")
GT_EDITION=$(cat /tmp/ground_truth_edition.txt 2>/dev/null || echo "Free")

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
PARSED_VERSION=""
PARSED_EDITION=""

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content (limit size for safety)
    FILE_CONTENT=$(head -c 1024 "$OUTPUT_PATH")
    
    # Simple parsing for JSON export (robust parsing in verifier.py)
    PARSED_VERSION=$(grep -i "Version:" "$OUTPUT_PATH" | head -1 | sed 's/Version://i' | xargs)
    PARSED_EDITION=$(grep -i "Edition:" "$OUTPUT_PATH" | head -1 | sed 's/Edition://i' | xargs)
fi

# 4. Check if App is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_raw": $(echo "$FILE_CONTENT" | jq -R .),
    "parsed_agent_version": "$PARSED_VERSION",
    "parsed_agent_edition": "$PARSED_EDITION",
    "ground_truth_version": "$GT_VERSION",
    "ground_truth_edition": "$GT_EDITION",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"