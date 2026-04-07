#!/bin/bash
echo "=== Exporting accessibility_visual_compliance result ==="

source /workspace/scripts/task_utils.sh

# Take final framework screenshot (evidence of state)
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check OpenICE State
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Check logs for device creation
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

DEVICE_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "device.*created|adapter.*started|multiparameter"; then
    DEVICE_CREATED="true"
fi

# 2. Check Artifacts
ORIGINAL_IMG="/home/ga/original_ui.png"
SCRIPT_FILE="/home/ga/process_accessibility.py"
GRAY_IMG="/home/ga/accessibility_proof_gray.png"
REPORT_FILE="/home/ga/luminance_report.txt"

# Function to gather file info
get_file_info() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        local created_during_task="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

INFO_ORIGINAL=$(get_file_info "$ORIGINAL_IMG")
INFO_SCRIPT=$(get_file_info "$SCRIPT_FILE")
INFO_GRAY=$(get_file_info "$GRAY_IMG")
INFO_REPORT=$(get_file_info "$REPORT_FILE")

# Read report content if exists
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 1 | tr -d '\n')
fi

# Verify image properties using Python (to check if gray image is actually grayscale)
# This runs inside the container to analyze the files before export
IMAGE_ANALYSIS=$(python3 -c "
import json
import os
from PIL import Image, ImageStat

result = {
    'original_valid': False,
    'gray_valid': False,
    'is_grayscale': False,
    'gray_dimensions': [0, 0],
    'original_dimensions': [0, 0]
}

try:
    if os.path.exists('$ORIGINAL_IMG'):
        with Image.open('$ORIGINAL_IMG') as img:
            result['original_valid'] = True
            result['original_dimensions'] = img.size
    
    if os.path.exists('$GRAY_IMG'):
        with Image.open('$GRAY_IMG') as img:
            result['gray_valid'] = True
            result['gray_dimensions'] = img.size
            # Check if image is grayscale (Mode 'L', '1' or RGB where R=G=B)
            if img.mode in ['L', '1']:
                result['is_grayscale'] = True
            elif img.mode == 'RGB':
                stat = ImageStat.Stat(img)
                if sum(stat.stddev) == 0: # Check if all channels identical (unlikely for complex image)
                     # Better check: compare bands
                     bands = img.split()
                     if bands[0].tobytes() == bands[1].tobytes() == bands[2].tobytes():
                         result['is_grayscale'] = True
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
" 2>/dev/null || echo "{}")

# Create result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "window_increase": $WINDOW_INCREASE,
    "device_created_log": $DEVICE_CREATED,
    "original_image": $INFO_ORIGINAL,
    "script_file": $INFO_SCRIPT,
    "gray_image": $INFO_GRAY,
    "report_file": $INFO_REPORT,
    "report_content": "$(escape_json_value "$REPORT_CONTENT")",
    "image_analysis": $IMAGE_ANALYSIS
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json