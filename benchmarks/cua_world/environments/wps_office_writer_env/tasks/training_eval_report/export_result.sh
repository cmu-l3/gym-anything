#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Training Evaluation Report Result ==="

# Bring window to front
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Take final screenshot
take_screenshot /tmp/training_eval_report_final.png

DOC_PATH="/home/ga/Documents/results/training_eval_report.docx"
DOC_EXISTS="false"
DOC_SIZE="0"

# Check if target file exists
if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    # Copy to tmp for safe parsing
    cp "$DOC_PATH" /tmp/training_eval_report.docx
    chmod 666 /tmp/training_eval_report.docx
    echo "Document successfully copied to /tmp/"
else
    # Check if they saved it in the wrong place but right name
    ALT_PATH="/home/ga/Documents/training_eval_report.docx"
    if [ -f "$ALT_PATH" ]; then
        DOC_EXISTS="true"
        DOC_SIZE=$(stat -c %s "$ALT_PATH" 2>/dev/null || echo "0")
        cp "$ALT_PATH" /tmp/training_eval_report.docx
        chmod 666 /tmp/training_eval_report.docx
        echo "Document found in alternative location and copied."
    fi
fi

TASK_START=$(cat /tmp/training_eval_report_start_ts 2>/dev/null || echo "0")

cat > /tmp/training_eval_report_result.json << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "task_start": $TASK_START,
    "screenshot": "/tmp/training_eval_report_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/training_eval_report_result.json

# Attempt to gracefully close WPS Writer
echo "Closing WPS Writer..."
safe_xdotool ga :1 key --delay 200 alt+F4
sleep 2

# Handle potential "Save Changes" dialog by pressing Tab then Enter (to select 'No' or 'Discard')
safe_xdotool ga :1 key --delay 100 Tab
sleep 0.3
safe_xdotool ga :1 key --delay 100 Return
sleep 0.5

# Force kill if still running
if pgrep -f "wps" > /dev/null; then
    pkill -f "wps" 2>/dev/null || true
fi

echo "=== Export Complete ==="