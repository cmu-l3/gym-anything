#!/bin/bash
# Export result for time_production_analysis
# The verifier reads the output JSON and the original data CSV directly from the environment

set -e
echo "=== Exporting time_production_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/timing_final_screenshot.png 2>/dev/null || true

# Pre-check for output to leave a trace in logs
REPORT_PATH="/home/ga/pebl/analysis/timing_report.json"
if [ -f "$REPORT_PATH" ]; then
    echo "Report found at $REPORT_PATH"
else
    echo "Warning: No report found at $REPORT_PATH"
fi

echo "=== time_production_analysis export complete ==="