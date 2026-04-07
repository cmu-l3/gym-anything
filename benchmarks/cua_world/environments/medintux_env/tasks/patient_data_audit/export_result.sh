#!/bin/bash
echo "=== Exporting patient_data_audit result ==="

REPORT_FILE="/home/ga/audit_report.csv"
GROUND_TRUTH_FILE="/tmp/ground_truth/incomplete_patients.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check report file status
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo 0)
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Prepare export package
# We copy everything to /tmp/export_staging for cleaner packaging if needed, 
# but here we'll just put things in /tmp/ for direct copy_from_env

# 1. Agent's Report
if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/agent_report.csv
else
    echo "No report found." > /tmp/agent_report.csv
fi

# 2. Ground Truth (generated during setup)
if [ -f "$GROUND_TRUTH_FILE" ]; then
    cp "$GROUND_TRUTH_FILE" /tmp/ground_truth.csv
else
    echo "No ground truth found." > /tmp/ground_truth.csv
fi

# 3. Metadata JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 644 /tmp/task_result.json /tmp/agent_report.csv /tmp/ground_truth.csv 2>/dev/null || true

echo "Export complete. Files ready in /tmp/"
ls -l /tmp/task_result.json /tmp/agent_report.csv /tmp/ground_truth.csv