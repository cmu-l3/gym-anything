#!/bin/bash
echo "=== Exporting radar_traffic_logging result ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/traffic_log.csv"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Traffic Safety Assessment"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output exists and when it was modified
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
CSV_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read content
    CSV_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check modification time
    MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Read Scenario Truth Data (to pass to verifier)
# We read the raw INI files so the verifier can calculate the physics ground truth
OWNSHIP_INI=$(cat "$SCENARIO_DIR/ownship.ini" 2>/dev/null | base64 -w 0)
OTHERSHIP_INI=$(cat "$SCENARIO_DIR/othership.ini" 2>/dev/null | base64 -w 0)

# 4. Create JSON Result
# We embed the CSV content and the Scenario INIs. 
# The Python verifier will do the physics math.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_content_base64": "$(echo "$CSV_CONTENT" | base64 -w 0)",
    "scenario_data": {
        "ownship_ini_base64": "$OWNSHIP_INI",
        "othership_ini_base64": "$OTHERSHIP_INI"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="