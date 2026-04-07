#!/bin/bash
# Export script for discounting_k_estimation task

set -e
echo "=== Exporting discounting_k_estimation result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Verify if the output file was created
if [ -f "/home/ga/pebl/analysis/discounting_report.json" ]; then
    echo "Output file found at /home/ga/pebl/analysis/discounting_report.json"
    ls -la /home/ga/pebl/analysis/discounting_report.json
else
    echo "WARNING: Output file NOT found at /home/ga/pebl/analysis/discounting_report.json"
fi

echo "=== Export complete ==="