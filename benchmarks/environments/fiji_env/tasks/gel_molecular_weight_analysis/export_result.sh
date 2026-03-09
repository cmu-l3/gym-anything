#!/bin/bash
echo "=== Exporting Gel Analysis Results ==="

RESULT_DIR="/home/ga/Fiji_Data/results/mw_analysis"
GT_FILE="/var/lib/fiji/ground_truth/gel_gt.json"
OUTPUT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/final_state.png 2>/dev/null || true

# Prepare result structure
REPORT_EXISTS="false"
PLOT_EXISTS="false"
REPORT_CONTENT="{}"
GT_CONTENT="{}"

if [ -f "$RESULT_DIR/report.json" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$RESULT_DIR/report.json")
fi

if [ -f "$RESULT_DIR/calibration_curve.png" ]; then
    PLOT_EXISTS="true"
fi

if [ -f "$GT_FILE" ]; then
    GT_CONTENT=$(cat "$GT_FILE")
fi

# Create export JSON using Python to handle nesting safely
python3 << PYEOF
import json
import os
import sys

try:
    report_content = json.loads('''$REPORT_CONTENT''') if '$REPORT_EXISTS' == 'true' else {}
except:
    report_content = {}

try:
    gt_content = json.loads('''$GT_CONTENT''')
except:
    gt_content = {}

result = {
    "report_exists": "$REPORT_EXISTS" == "true",
    "plot_exists": "$PLOT_EXISTS" == "true",
    "agent_report": report_content,
    "ground_truth": gt_content,
    "screenshot_path": "/tmp/final_state.png"
}

with open('$OUTPUT_JSON', 'w') as f:
    json.dump(result, f)
PYEOF

echo "Export saved to $OUTPUT_JSON"
cat "$OUTPUT_JSON"