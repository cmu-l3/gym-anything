#!/bin/bash
# export_result.sh - Export results for inhalation_risk_ranking task

echo "=== Exporting Inhalation Risk Ranking Results ==="

# 1. Define paths
OUTPUT_FILE="/home/ga/Documents/inhalation_risk_assessment.csv"
RESULT_JSON="/tmp/task_result.json"
START_TIME_FILE="/tmp/task_start_time.txt"

# 2. Capture final screenshot (Evidence of state at end)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check for Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    
    # Check modification time against start time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate Result JSON
# We use a temp file to ensure atomic write and avoid permission issues
TEMP_JSON=$(mktemp)

cat <<EOF > "$TEMP_JSON"
{
  "output_exists": $OUTPUT_EXISTS,
  "output_size_bytes": $OUTPUT_SIZE,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_path": "$OUTPUT_FILE",
  "screenshot_path": "/tmp/task_final.png",
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location (accessible by copy_from_env)
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
echo "=== Export Complete ==="