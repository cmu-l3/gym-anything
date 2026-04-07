#!/bin/bash
set -euo pipefail

echo "=== Exporting track_moving_asteroid result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect timestamps and file state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_CSV="/home/ga/AstroImages/measurements/asteroid_track.csv"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

# Check if the exact expected file exists
if [ -f "$OUTPUT_CSV" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_CSV" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy for verifier
    cp "$OUTPUT_CSV" /tmp/agent_measurements.csv
    chmod 666 /tmp/agent_measurements.csv
else
    # Fallback: check if ANY csv was created in the measurements dir during the task
    FALLBACK_CSV=$(find /home/ga/AstroImages/measurements/ -name "*.csv" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$FALLBACK_CSV" ]; then
        FILE_EXISTS="true"
        FILE_CREATED_DURING_TASK="true"
        FILE_SIZE=$(stat -c %s "$FALLBACK_CSV" 2>/dev/null || echo "0")
        echo "Found fallback CSV: $FALLBACK_CSV"
        cp "$FALLBACK_CSV" /tmp/agent_measurements.csv
        chmod 666 /tmp/agent_measurements.csv
    fi
fi

# 3. Check if app is still running
APP_RUNNING=$(pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null && echo "true" || echo "false")

# 4. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING
}
EOF

# Ensure safe move and permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported successfully."
cat /tmp/task_result.json