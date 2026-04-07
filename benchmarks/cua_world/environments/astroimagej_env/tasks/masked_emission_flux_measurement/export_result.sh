#!/bin/bash
echo "=== Exporting Masked Emission Flux Measurement Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUT_DIR="/home/ga/AstroImages/emission_analysis/output"
REPORT_FILE="$OUT_DIR/emission_report.txt"

# Check for mask files
MASK_FILE_FOUND="false"
MASK_FILE_PATH=""
MASK_FILE_CREATED_DURING_TASK="false"

# Check possible mask names (.tif, .fits, etc.)
for ext in tif tiff fits fit; do
    potential_mask="$OUT_DIR/emission_mask.$ext"
    if [ -f "$potential_mask" ]; then
        MASK_FILE_FOUND="true"
        MASK_FILE_PATH="$potential_mask"
        # Check creation time
        mtime=$(stat -c %Y "$potential_mask" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            MASK_FILE_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

# If not found, check other files in OUT_DIR
if [ "$MASK_FILE_FOUND" = "false" ]; then
    for f in "$OUT_DIR"/*mask*; do
        if [ -f "$f" ]; then
            MASK_FILE_FOUND="true"
            MASK_FILE_PATH="$f"
            mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$mtime" -gt "$TASK_START" ]; then
                MASK_FILE_CREATED_DURING_TASK="true"
            fi
            break
        fi
    done
fi

# Check for report file
REPORT_FILE_FOUND="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_FILE_FOUND="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 4000)
    mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$mtime" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
else
    # Try finding any txt file in output
    alt_report=$(ls -1 "$OUT_DIR"/*.txt 2>/dev/null | head -1)
    if [ -f "$alt_report" ]; then
        REPORT_FILE_FOUND="true"
        REPORT_CONTENT=$(cat "$alt_report" | head -c 4000)
        mtime=$(stat -c %Y "$alt_report" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Check if AIJ is running
AIJ_RUNNING="false"
if is_aij_running; then
    AIJ_RUNNING="true"
fi

# Build result JSON using python to safely escape strings
python3 << PYEOF
import json
import os

result = {
    "mask_file_found": "$MASK_FILE_FOUND" == "true",
    "mask_file_path": "$MASK_FILE_PATH",
    "mask_file_created_during_task": "$MASK_FILE_CREATED_DURING_TASK" == "true",
    "report_file_found": "$REPORT_FILE_FOUND" == "true",
    "report_created_during_task": "$REPORT_CREATED_DURING_TASK" == "true",
    "report_content": """$REPORT_CONTENT""",
    "aij_running": "$AIJ_RUNNING" == "true"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="