#!/bin/bash
echo "=== Exporting create_hoq_qfd_diagram results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EDDX_PATH="/home/ga/Documents/laptop_qfd.eddx"
PDF_PATH="/home/ga/Documents/laptop_qfd.pdf"

# Function to gather file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        # Check if created/modified AFTER task start
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
PDF_INFO=$(get_file_info "$PDF_PATH")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_file": $EDDX_INFO,
    "pdf_file": $PDF_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="