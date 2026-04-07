#!/bin/bash
set -e
echo "=== Exporting metacognition_calibration_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot for visual evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Copy the agent's output JSON to /tmp for easy access by copy_from_env
REPORT_PATH="/home/ga/pebl/analysis/metacognition_report.json"
if [ -f "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" /tmp/metacognition_report.json
    chmod 644 /tmp/metacognition_report.json
    echo "Output file found and exported."
else
    echo "WARNING: Output file not found at $REPORT_PATH"
fi

echo "=== Export complete ==="