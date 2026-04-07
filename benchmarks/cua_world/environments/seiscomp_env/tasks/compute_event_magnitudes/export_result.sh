#!/bin/bash
echo "=== Exporting compute_event_magnitudes result ==="

# Record task end time
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

EVENT_ID=$(cat /tmp/target_event_id.txt 2>/dev/null)

# Query Database for new Amplitudes and Magnitudes
AMP_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Amplitude" 2>/dev/null || echo "0")
MAG_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Magnitude" 2>/dev/null || echo "0")

# Extract the computed magnitude values from the DB (if they exist)
DB_MB_VAL=$(mysql -u sysop -psysop seiscomp -N -e "SELECT magnitude_value FROM Magnitude WHERE type='mb' LIMIT 1" 2>/dev/null | awk '{print $1}')
DB_MLV_VAL=$(mysql -u sysop -psysop seiscomp -N -e "SELECT magnitude_value FROM Magnitude WHERE type='MLv' LIMIT 1" 2>/dev/null | awk '{print $1}')

# Check for the report file
REPORT_PATH="/home/ga/magnitude_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Replace newlines with | for easier JSON embedding, and escape quotes
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr '\n' '|' | sed 's/"/\\"/g')
    
    # Check timestamp
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_end": $TASK_END,
    "event_id": "$EVENT_ID",
    "final_amp_count": $AMP_COUNT,
    "final_mag_count": $MAG_COUNT,
    "db_mb_val": "${DB_MB_VAL}",
    "db_mlv_val": "${DB_MLV_VAL}",
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="