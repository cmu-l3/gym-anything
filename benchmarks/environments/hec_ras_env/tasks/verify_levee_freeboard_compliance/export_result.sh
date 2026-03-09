#!/bin/bash
echo "=== Exporting Verify Levee Freeboard Compliance Result ==="

source /workspace/scripts/task_utils.sh

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
OUTPUT_CSV="$RESULTS_DIR/levee_compliance.csv"
OUTPUT_PLOT="$RESULTS_DIR/levee_profile.png"
GT_FILE="/var/lib/hec_ras/ground_truth/levee_compliance_gt.csv"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Existence
CSV_EXISTS="false"
PLOT_EXISTS="false"
SCRIPT_EXISTS="false"

if [ -f "$OUTPUT_CSV" ]; then CSV_EXISTS="true"; fi
if [ -f "$OUTPUT_PLOT" ]; then PLOT_EXISTS="true"; fi

# Look for python scripts created by agent
AGENT_SCRIPTS=$(find "$RESULTS_DIR" -name "*.py" 2>/dev/null | wc -l)
if [ "$AGENT_SCRIPTS" -gt 0 ]; then SCRIPT_EXISTS="true"; fi

# 3. Copy files to tmp for verifier
cp "$OUTPUT_CSV" /tmp/agent_output.csv 2>/dev/null || true
cp "$GT_FILE" /tmp/ground_truth.csv 2>/dev/null || true

# 4. JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "plot_exists": $PLOT_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "agent_csv_path": "/tmp/agent_output.csv",
    "ground_truth_path": "/tmp/ground_truth.csv",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"