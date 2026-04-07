#!/bin/bash
# Export result for axcpt_proactive_control_analysis

set -e
echo "=== Exporting axcpt_proactive_control_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for trajectory/evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/axcpt_final_screenshot.png 2>/dev/null || true

# Check if the output JSON was created during the task
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/pebl/analysis/axcpt_report.json"
FILE_CREATED="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
fi

# The verifier reads the output JSON directly from the environment using copy_from_env
# We just log basic state here for debug purposes
echo "Report generated: $FILE_CREATED"
echo "=== axcpt_proactive_control_analysis export complete ==="