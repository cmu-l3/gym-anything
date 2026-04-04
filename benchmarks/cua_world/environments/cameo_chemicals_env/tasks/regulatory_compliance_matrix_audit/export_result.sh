#!/bin/bash
# export_result.sh - Post-task hook for regulatory_compliance_matrix_audit

set -e
echo "=== Exporting task results ==="

# Define paths
OUTPUT_FILE="/home/ga/Desktop/compliance_matrix.csv"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Check output file status
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if application (Firefox) is still running
APP_RUNNING="false"
if pgrep -u ga -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
# We use a python one-liner or simple cat to generate valid JSON
cat > "$RESULT_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_exists": $FILE_EXISTS,
  "output_size_bytes": $FILE_SIZE,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "app_was_running": $APP_RUNNING,
  "output_path": "$OUTPUT_FILE",
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure the result file is readable by the verifier (host)
chmod 644 "$RESULT_JSON"
chmod 644 /tmp/task_final.png 2>/dev/null || true

if [ "$FILE_EXISTS" = "true" ]; then
    chmod 644 "$OUTPUT_FILE"
fi

echo "Results exported to $RESULT_JSON"
echo "=== Export complete ==="