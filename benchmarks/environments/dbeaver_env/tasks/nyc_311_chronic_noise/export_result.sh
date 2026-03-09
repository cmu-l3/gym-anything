#!/bin/bash
echo "=== Exporting NYC Noise Analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_FILE="/home/ga/Documents/exports/chronic_addresses.csv"
SCRIPT_FILE="/home/ga/Documents/scripts/noise_analysis.sql"
DATA_FILE="/home/ga/Documents/data/nyc_noise.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output CSV
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING_TASK="false"
if [ -f "$EXPORT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Check SQL script
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
fi

# Check DBeaver Connection
# We look into DBeaver's configuration to see if a connection named 'CityData' exists
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONNECTION_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -qi "CityData" "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# Copy files to /tmp for verifier access (handling permissions)
# We copy the source data too so the verifier can calculate ground truth dynamically
cp "$DATA_FILE" /tmp/source_data.csv 2>/dev/null || true
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$EXPORT_FILE" /tmp/agent_output.csv 2>/dev/null || true
fi
if [ "$SCRIPT_EXISTS" = "true" ]; then
    cp "$SCRIPT_FILE" /tmp/agent_script.sql 2>/dev/null || true
fi
chmod 644 /tmp/source_data.csv /tmp/agent_output.csv /tmp/agent_script.sql 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "script_exists": $SCRIPT_EXISTS,
    "connection_exists": $CONNECTION_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."