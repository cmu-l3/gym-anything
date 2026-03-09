#!/bin/bash
echo "=== Exporting create_cased_line_style result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check if style exists in 'ne' workspace
STYLE_NAME="river_casing"
WORKSPACE="ne"
STYLE_EXISTS="false"
STYLE_CONTENT=""
STYLE_FORMAT=""

# Check REST API for style
HTTP_CODE=$(gs_rest_status "workspaces/$WORKSPACE/styles/$STYLE_NAME.json")
if [ "$HTTP_CODE" = "200" ]; then
    STYLE_EXISTS="true"
    # Get the SLD content
    STYLE_CONTENT=$(gs_rest_get_xml "workspaces/$WORKSPACE/styles/$STYLE_NAME.sld")
    # Get format
    STYLE_META=$(gs_rest_get "workspaces/$WORKSPACE/styles/$STYLE_NAME.json")
    STYLE_FORMAT=$(echo "$STYLE_META" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('style',{}).get('format',''))" 2>/dev/null)
fi

# 4. Check Layer Association (ne:ne_rivers)
LAYER_DEFAULT_STYLE=""
LAYER_CHECK=$(gs_rest_get "workspaces/ne/layers/ne_rivers.json")
if [ -n "$LAYER_CHECK" ]; then
    LAYER_DEFAULT_STYLE=$(echo "$LAYER_CHECK" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)
fi

# 5. Check Output Image
OUTPUT_IMG="/home/ga/output/rivers_regional.png"
IMG_EXISTS="false"
IMG_CREATED_DURING_TASK="false"
IMG_SIZE="0"

if [ -f "$OUTPUT_IMG" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$OUTPUT_IMG")
    IMG_MTIME=$(stat -c %Y "$OUTPUT_IMG")
    
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING_TASK="true"
    fi
fi

# 6. Check for GUI interaction
GUI_INTERACTION=$(check_gui_interaction)

# 7. Build Result JSON
# We treat the SLD content carefully to avoid breaking JSON with newlines/quotes
# Using Python to construct the JSON safely
python3 -c "
import json
import os
import sys

def safe_read(path):
    try:
        with open(path, 'r') as f: return f.read()
    except: return ''

data = {
    'style_exists': '$STYLE_EXISTS' == 'true',
    'style_name': '$STYLE_NAME',
    'style_content': sys.argv[1],
    'style_format': '$STYLE_FORMAT',
    'layer_default_style': '$LAYER_DEFAULT_STYLE',
    'image_exists': '$IMG_EXISTS' == 'true',
    'image_created_during_task': '$IMG_CREATED_DURING_TASK' == 'true',
    'image_size': int('$IMG_SIZE'),
    'image_path': '$OUTPUT_IMG',
    'gui_interaction': '$GUI_INTERACTION' == 'true',
    'result_nonce': '$(get_result_nonce)',
    'task_duration': int('$TASK_END') - int('$TASK_START')
}

with open('/tmp/create_cased_line_result.json', 'w') as f:
    json.dump(data, f)
" "$STYLE_CONTENT"

# 8. Secure copy to standardized location
safe_write_result "/tmp/create_cased_line_result.json" "/tmp/task_result.json"

echo "=== Export complete ==="