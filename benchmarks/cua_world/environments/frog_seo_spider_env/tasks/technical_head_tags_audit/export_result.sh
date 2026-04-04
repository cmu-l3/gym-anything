#!/bin/bash
# Export script for Technical Head Tags Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Technical Head Tags Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TARGET_FILE="$EXPORT_DIR/head_tags_audit.csv"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
ROW_COUNT=0
HAS_VIEWPORT="false"
HAS_FAVICON="false"
HAS_CHARSET="false"
HEADER_LINE=""
SAMPLE_DATA=""
SF_RUNNING="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Check target file
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check creation time
    FILE_EPOCH=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Analyze content
    ROW_COUNT=$(wc -l < "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$ROW_COUNT" -gt 0 ]; then
        ROW_COUNT=$((ROW_COUNT - 1)) # Subtract header
    fi
    
    # Read header and a sample line
    HEADER_LINE=$(head -1 "$TARGET_FILE" 2>/dev/null || echo "")
    SAMPLE_DATA=$(head -5 "$TARGET_FILE" 2>/dev/null || echo "")
    
    # Check for Viewport data (look for "width" or "device-width")
    if echo "$SAMPLE_DATA" | grep -qi "width=\|device-width\|scale"; then
        HAS_VIEWPORT="true"
    fi
    
    # Check for Favicon data (look for ".ico" or "icon")
    if echo "$SAMPLE_DATA" | grep -qi "\.ico\|icon\|static/oscar"; then
        HAS_FAVICON="true"
    fi
    
    # Check for Charset data (look for "utf" or "text/html")
    if echo "$SAMPLE_DATA" | grep -qi "utf-8\|utf8\|iso-\|text/html"; then
        HAS_CHARSET="true"
    fi
    
    # Fallback: Check headers if sample data is ambiguous, but strict on content usually
    # If the user named columns explicitly "Viewport", "Favicon", etc.
    if echo "$HEADER_LINE" | grep -qi "Viewport"; then HAS_VIEWPORT="true"; fi
    if echo "$HEADER_LINE" | grep -qi "Favicon"; then HAS_FAVICON="true"; fi
    if echo "$HEADER_LINE" | grep -qi "Charset"; then HAS_CHARSET="true"; fi
fi

# Check for window title info (as backup evidence)
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Write result JSON using Python
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING == "true",
    "file_exists": "$FILE_EXISTS" == "true",
    "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "file_path": "$TARGET_FILE",
    "row_count": $ROW_COUNT,
    "has_viewport_data": "$HAS_VIEWPORT" == "true",
    "has_favicon_data": "$HAS_FAVICON" == "true",
    "has_charset_data": "$HAS_CHARSET" == "true",
    "header_line": """$HEADER_LINE""",
    "window_info": """$WINDOW_INFO""",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="