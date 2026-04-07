#!/bin/bash
set -e
echo "=== Exporting create_custom_stylesheet result ==="

# Source utility functions if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    TIDDLER_DIR="/home/ga/mywiki/tiddlers"
    take_screenshot() {
        DISPLAY=:1 import -window root "$1" 2>/dev/null || DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract state variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TIDDLER_EXISTS="false"
CREATED_DURING_TASK="false"
HAS_STYLESHEET_TAG="false"
HAS_CSS_TYPE="false"
API_STATUS="000"
FILE_PATH=""
COLORS_FOUND=0
COLORS_LIST=""

# 3. Find the tiddler file (Search by title content to be robust against filename variations)
FOUND_FILE=$(grep -l "^title: Custom Dark Theme" "$TIDDLER_DIR"/*.tid 2>/dev/null | head -1)

if [ -z "$FOUND_FILE" ]; then
    # Fallback to checking the exact filename if title formatting varied
    if [ -f "$TIDDLER_DIR/Custom Dark Theme.tid" ]; then
        FOUND_FILE="$TIDDLER_DIR/Custom Dark Theme.tid"
    elif [ -f "$TIDDLER_DIR/Custom_Dark_Theme.tid" ]; then
        FOUND_FILE="$TIDDLER_DIR/Custom_Dark_Theme.tid"
    fi
fi

if [ -n "$FOUND_FILE" ] && [ -f "$FOUND_FILE" ]; then
    TIDDLER_EXISTS="true"
    FILE_PATH="$FOUND_FILE"
    
    # Check creation/modification time
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Check tags and type
    if grep -qi "tags:.*\$:/tags/Stylesheet" "$FOUND_FILE"; then
        HAS_STYLESHEET_TAG="true"
    fi
    
    if grep -qi "type:.*text/css" "$FOUND_FILE"; then
        HAS_CSS_TYPE="true"
    fi
    
    # Check for target colors
    CONTENT=$(cat "$FOUND_FILE")
    for color in "#1e1e2e" "#cdd6f4" "#181825" "#cba6f7" "#89b4fa"; do
        if echo "$CONTENT" | grep -qi "$color"; then
            COLORS_FOUND=$((COLORS_FOUND + 1))
            COLORS_LIST="$COLORS_LIST $color"
        fi
    done
fi

# 4. Check API accessibility
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/recipes/default/tiddlers/Custom%20Dark%20Theme" || echo "000")
API_STATUS="$API_RESPONSE"

# Check API content if file wasn't found (fallback)
if [ "$TIDDLER_EXISTS" = "false" ] && [ "$API_STATUS" = "200" ]; then
    TIDDLER_EXISTS="true"
    CREATED_DURING_TASK="true" # Assuming it was created in this session if it's in API but not file
    API_CONTENT=$(curl -s "http://localhost:8080/recipes/default/tiddlers/Custom%20Dark%20Theme")
    
    if echo "$API_CONTENT" | grep -qi "\$:/tags/Stylesheet"; then HAS_STYLESHEET_TAG="true"; fi
    if echo "$API_CONTENT" | grep -qi "text/css"; then HAS_CSS_TYPE="true"; fi
    
    for color in "#1e1e2e" "#cdd6f4" "#181825" "#cba6f7" "#89b4fa"; do
        if echo "$API_CONTENT" | grep -qi "$color"; then
            COLORS_FOUND=$((COLORS_FOUND + 1))
            COLORS_LIST="$COLORS_LIST $color"
        fi
    done
fi

# 5. Build Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tiddler_exists": $TIDDLER_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "has_stylesheet_tag": $HAS_STYLESHEET_TAG,
    "has_css_type": $HAS_CSS_TYPE,
    "api_status": "$API_STATUS",
    "colors_found_count": $COLORS_FOUND,
    "colors_found_list": "$COLORS_LIST",
    "file_path": "$FILE_PATH"
}
EOF

# Safely copy to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="