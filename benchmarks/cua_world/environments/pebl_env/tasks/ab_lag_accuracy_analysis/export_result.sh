#!/bin/bash
# Export result for ab_lag_accuracy_analysis
# The verifier reads the JSON output directly from the environment using copy_from_env

set -e
echo "=== Exporting ab_lag_accuracy_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/ab_final_screenshot.png 2>/dev/null || true

# Result file size check
if [ -f /home/ga/pebl/analysis/ab_report.json ]; then
    echo "Output file found: $(stat -c %s /home/ga/pebl/analysis/ab_report.json) bytes"
else
    echo "Output file NOT found."
fi

echo "=== ab_lag_accuracy_analysis export complete ==="