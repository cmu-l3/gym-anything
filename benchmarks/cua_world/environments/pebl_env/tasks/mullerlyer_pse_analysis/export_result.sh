#!/bin/bash
# Export script for mullerlyer_pse_analysis task

echo "=== Exporting mullerlyer_pse_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Verification handles reading the JSON directly using copy_from_env.
# We just verify the file exists as a quick debug output.
REPORT_FILE="/home/ga/pebl/analysis/mullerlyer_report.json"
if [ -f "$REPORT_FILE" ]; then
    echo "Output report found at $REPORT_FILE."
    echo "Size: $(stat -c %s "$REPORT_FILE") bytes."
else
    echo "WARNING: Output report NOT found at $REPORT_FILE."
fi

echo "=== Export complete ==="