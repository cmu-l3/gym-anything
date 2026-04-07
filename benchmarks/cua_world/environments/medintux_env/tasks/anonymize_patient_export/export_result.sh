#!/bin/bash
echo "=== Exporting anonymize_patient_export results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

CSV_PATH="/home/ga/research_export/anonymized_patients.csv"
AUDIT_PATH="/home/ga/research_export/anonymization_audit.txt"

# Check CSV status
if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    else
        CSV_CREATED_DURING_TASK="false"
    fi
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
else
    CSV_EXISTS="false"
    CSV_CREATED_DURING_TASK="false"
    CSV_SIZE="0"
fi

# Check Audit status
if [ -f "$AUDIT_PATH" ]; then
    AUDIT_MTIME=$(stat -c %Y "$AUDIT_PATH" 2>/dev/null || echo "0")
    if [ "$AUDIT_MTIME" -gt "$TASK_START" ]; then
        AUDIT_CREATED_DURING_TASK="true"
    else
        AUDIT_CREATED_DURING_TASK="false"
    fi
    AUDIT_EXISTS="true"
    AUDIT_SIZE=$(stat -c %s "$AUDIT_PATH" 2>/dev/null || echo "0")
else
    AUDIT_EXISTS="false"
    AUDIT_CREATED_DURING_TASK="false"
    AUDIT_SIZE="0"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    "audit_exists": $AUDIT_EXISTS,
    "audit_created_during_task": $AUDIT_CREATED_DURING_TASK,
    "audit_size_bytes": $AUDIT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="