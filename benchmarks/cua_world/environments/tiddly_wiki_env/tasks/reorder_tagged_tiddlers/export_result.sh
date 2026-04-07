#!/bin/bash
set -e
echo "=== Exporting reorder_tagged_tiddlers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Query TiddlyWiki API for the IncidentResponse tiddler
API_RESP=$(curl -s http://localhost:8080/recipes/default/tiddlers/IncidentResponse || echo "{}")

# Check if it was successfully retrieved
if echo "$API_RESP" | jq -e '.title == "IncidentResponse"' > /dev/null 2>&1; then
    TIDDLER_EXISTS="true"
    
    # Try to find the actual file to check creation/modification time
    # (TiddlyWiki might have sanitized the filename slightly, but exact title match via grep is safe)
    TIDDLER_FILE=$(find "$TIDDLER_DIR" -name "*.tid" -exec grep -l "^title: IncidentResponse$" {} \; | head -1)
    if [ -n "$TIDDLER_FILE" ] && [ -f "$TIDDLER_FILE" ]; then
        MTIME=$(stat -c %Y "$TIDDLER_FILE")
    else
        MTIME=0
    fi
else
    TIDDLER_EXISTS="false"
    MTIME=0
    API_RESP="{}"
fi

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

# Check TiddlyWiki server log for GUI save events
GUI_SAVE="false"
if grep -q "Dispatching 'save' task: IncidentResponse" /home/ga/tiddlywiki.log 2>/dev/null; then
    GUI_SAVE="true"
fi

# Create export JSON safely
TEMP_JSON=$(mktemp /tmp/export.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "mtime": $MTIME,
    "tiddler_exists": $TIDDLER_EXISTS,
    "gui_save_detected": $GUI_SAVE,
    "tiddler_data": $API_RESP,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="