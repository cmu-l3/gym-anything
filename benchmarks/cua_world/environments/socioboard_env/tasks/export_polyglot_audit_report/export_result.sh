#!/bin/bash
echo "=== Exporting Polyglot Audit Report result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/workspace/audit_report.csv"
GT_PATH="/var/lib/socioboard_audit/ground_truth.json"

CSV_EXISTS="false"
CREATED_DURING_TASK="false"
CSV_SIZE="0"

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check for generated report and copy for verification
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Copy output payload to /tmp for easy retrieval
    cp "$CSV_PATH" /tmp/audit_report.csv 2>/dev/null || sudo cp "$CSV_PATH" /tmp/audit_report.csv
    chmod 666 /tmp/audit_report.csv 2>/dev/null || sudo chmod 666 /tmp/audit_report.csv
fi

# Copy ground truth payload to /tmp
cp "$GT_PATH" /tmp/ground_truth.json 2>/dev/null || sudo cp "$GT_PATH" /tmp/ground_truth.json
chmod 666 /tmp/ground_truth.json 2>/dev/null || sudo chmod 666 /tmp/ground_truth.json

# Create summary JSON
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    "task_start_time": $TASK_START
}
EOF
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Export completed successfully."