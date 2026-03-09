#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CSV_PATH="/home/ga/Documents/hec_ras_results/transition_audit.csv"
REPORT_PATH="/home/ga/Documents/hec_ras_results/transition_report.txt"
GT_PATH="/tmp/ground_truth.json"

# Check output files
CSV_EXISTS="false"
REPORT_EXISTS="false"
CSV_ROWS=0
REPORT_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        CSV_ROWS=$(wc -l < "$CSV_PATH" || echo "0")
    fi
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    fi
fi

# Check for Python script creation (Evidence of work)
SCRIPT_CREATED="false"
SCRIPTS=$(find /home/ga/Documents -name "*.py" -newermt "@$TASK_START" 2>/dev/null)
if [ -n "$SCRIPTS" ]; then
    SCRIPT_CREATED="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare files for export (copy to /tmp/ for easy extraction by verifier)
cp "$GT_PATH" /tmp/ground_truth_export.json 2>/dev/null || echo "{}" > /tmp/ground_truth_export.json
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/agent_audit.csv
else
    touch /tmp/agent_audit.csv
fi
if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_PATH" /tmp/agent_report.txt
else
    touch /tmp/agent_report.txt
fi

chmod 644 /tmp/ground_truth_export.json /tmp/agent_audit.csv /tmp/agent_report.txt

# JSON Result for metadata
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "report_exists": $REPORT_EXISTS,
    "script_created": $SCRIPT_CREATED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete."