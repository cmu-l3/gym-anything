#!/bin/bash
echo "=== Exporting create_uml_timing_diagram results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_PATH="/home/ga/Documents/entry_timing.eddx"
PNG_PATH="/home/ga/Documents/entry_timing.png"

# Helper function to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        # Check if modified/created AFTER task start
        local fresh="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            fresh="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"fresh\": $fresh}"
    else
        echo "{\"exists\": false, \"size\": 0, \"fresh\": false}"
    fi
}

EDDX_INFO=$(get_file_info "$EDDX_PATH")
PNG_INFO=$(get_file_info "$PNG_PATH")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_file": $EDDX_INFO,
    "png_file": $PNG_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with proper permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="