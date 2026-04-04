#!/bin/bash
echo "=== Exporting customize_library_columns result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing app (for visual verification if needed)
take_screenshot /tmp/task_final.png

# 1. Gracefully close Jurism to flush settings to xulstore.json
# XUL apps write interface state to xulstore.json on exit
echo "Closing Jurism to save settings..."
pkill -f /opt/jurism/jurism
# Wait for process to exit and file to be written
sleep 5

# 2. Locate xulstore.json
PROFILE_DIR=""
for profile_base in /home/ga/.jurism/jurism /home/ga/.zotero/zotero; do
    found=$(find "$profile_base" -maxdepth 1 -type d -name "*.default" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        PROFILE_DIR="$found"
        break
    fi
done

XULSTORE_JSON="{}"
XULSTORE_MTIME="0"
XULSTORE_PATH=""

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/xulstore.json" ]; then
    XULSTORE_PATH="$PROFILE_DIR/xulstore.json"
    XULSTORE_MTIME=$(stat -c %Y "$XULSTORE_PATH" 2>/dev/null || echo "0")
    
    # Read relevant content using python to avoid massive JSON dump
    # We specifically look for the columns we care about
    XULSTORE_JSON=$(python3 -c "
import json
import sys

try:
    with open('$XULSTORE_PATH', 'r') as f:
        data = json.load(f)
    
    # Extract only the relevant column states to keep result clean
    # The key is usually zotero-items-columns-header or specific IDs
    result = {}
    
    def find_keys(obj, target_keys):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k in target_keys:
                    result[k] = v
                else:
                    find_keys(v, target_keys)
    
    targets = ['zotero-items-column-dateAdded', 'zotero-items-column-itemType', 'zotero-items-column-date', 'zotero-items-column-title']
    find_keys(data, targets)
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo "{}")
else
    echo "WARNING: xulstore.json not found in $PROFILE_DIR"
fi

# Check if file was modified during task
FILE_MODIFIED_DURING_TASK="false"
if [ "$XULSTORE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "xulstore_path": "$XULSTORE_PATH",
    "xulstore_mtime": $XULSTORE_MTIME,
    "settings_modified": $FILE_MODIFIED_DURING_TASK,
    "column_states": $XULSTORE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="