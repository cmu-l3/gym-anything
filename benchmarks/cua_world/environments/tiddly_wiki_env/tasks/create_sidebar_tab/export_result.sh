#!/bin/bash
echo "=== Exporting create_sidebar_tab result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

TIDDLER_DIR="/home/ga/mywiki/tiddlers"
TID_FILE="$TIDDLER_DIR/\$__custom_ProjectDashboard.tid"
FOUND_FILE=""

# Find the newly created tiddler file
if [ -f "$TID_FILE" ]; then
    FOUND_FILE="$TID_FILE"
else
    # Try fuzzy matching in case of escaping differences
    FOUND_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name '*custom*ProjectDashboard*' 2>/dev/null | head -1)
fi

# Fallback: any tiddler with SideBar tag and Projects caption created
if [ -z "$FOUND_FILE" ]; then
    FOUND_FILE=$(grep -l "caption: Projects" "$TIDDLER_DIR"/*.tid 2>/dev/null | xargs grep -l "\$:/tags/SideBar" 2>/dev/null | head -1)
fi

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
HAS_SIDEBAR_TAG="false"
HAS_CAPTION="false"
HAS_LIST_WIDGET="false"
HAS_FILTER="false"
HAS_SORT="false"

if [ -n "$FOUND_FILE" ] && [ -f "$FOUND_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check if file was created/modified during task
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    CONTENT=$(cat "$FOUND_FILE")
    
    echo "$CONTENT" | grep -qi 'tags:.*\$:/tags/SideBar' && HAS_SIDEBAR_TAG="true"
    echo "$CONTENT" | grep -qi 'caption:.*Projects' && HAS_CAPTION="true"
    echo "$CONTENT" | grep -qi '<\$list' && HAS_LIST_WIDGET="true"
    echo "$CONTENT" | grep -qi 'tag\[ProjectAlpha\]' && HAS_FILTER="true"
    echo "$CONTENT" | grep -qi 'sort\[title\]' && HAS_SORT="true"
fi

# Verify via local API
API_OK="false"
API_RESPONSE=$(curl -s "http://localhost:8080/recipes/default/tiddlers/%24%3A%2Fcustom%2FProjectDashboard" 2>/dev/null || echo "")
if echo "$API_RESPONSE" | grep -q '"title":'; then
    if echo "$API_RESPONSE" | grep -qi 'SideBar' && echo "$API_RESPONSE" | grep -qi 'Projects'; then
        API_OK="true"
    fi
fi

# Server log check for GUI action proof
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*ProjectDashboard" /home/ga/tiddlywiki.log 2>/dev/null || \
       grep -qi "Dispatching 'save' task:.*Projects" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_sidebar_tag": $HAS_SIDEBAR_TAG,
    "has_caption": $HAS_CAPTION,
    "has_list_widget": $HAS_LIST_WIDGET,
    "has_filter": $HAS_FILTER,
    "has_sort": $HAS_SORT,
    "api_verified": $API_OK,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="