#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Emergency Action Plan Format Result ==="

# Focus WPS Window for final screenshot
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi
sleep 1
take_screenshot /tmp/emergency_action_plan_end_screenshot.png

INPUT_PATH="/home/ga/Documents/emergency_action_plan_raw.docx"
OUTPUT_PATH="/home/ga/Documents/emergency_action_plan_formatted.docx"

DOC_EXISTS="false"
DOC_SIZE="0"
DOC_MTIME="0"

# Check if the formatted document exists
if [ -f "$OUTPUT_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Copy to /tmp for host-side verification
    cp "$OUTPUT_PATH" /tmp/emergency_action_plan_formatted.docx
    chmod 666 /tmp/emergency_action_plan_formatted.docx
    echo "Document copied to /tmp/"
else
    # Fallback to the original document if they saved over it
    if [ -f "$INPUT_PATH" ]; then
        DOC_SIZE=$(stat -c %s "$INPUT_PATH" 2>/dev/null || echo "0")
        DOC_MTIME=$(stat -c %Y "$INPUT_PATH" 2>/dev/null || echo "0")
        # Copy to /tmp so verifier can at least check it
        cp "$INPUT_PATH" /tmp/emergency_action_plan_formatted.docx
        chmod 666 /tmp/emergency_action_plan_formatted.docx
        echo "Agent saved over original document. Copied to /tmp/"
    fi
fi

TASK_START=$(cat /tmp/emergency_action_plan_start_ts 2>/dev/null || echo "0")

# Write results
cat > /tmp/emergency_action_plan_result.json << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$OUTPUT_PATH",
    "document_size": $DOC_SIZE,
    "document_mtime": $DOC_MTIME,
    "task_start": $TASK_START,
    "screenshot": "/tmp/emergency_action_plan_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/emergency_action_plan_result.json

# Close WPS Writer cleanly
echo "Closing WPS Writer..."
safe_xdotool ga :1 key --delay 200 alt+F4
sleep 2

# Handle "Save Changes?" dialog just in case
safe_xdotool ga :1 key --delay 100 Tab
sleep 0.3
safe_xdotool ga :1 key --delay 100 Return
sleep 0.5

# Fallback kill
if pgrep -f "wps" > /dev/null; then
    pkill -f wps 2>/dev/null || true
fi

echo "=== Export Complete ==="