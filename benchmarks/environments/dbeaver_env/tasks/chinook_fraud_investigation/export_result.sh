#!/bin/bash
# Export script for chinook_fraud_investigation
# Validates output existence, timestamp, and basic DBeaver state

echo "=== Exporting Fraud Investigation Result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_CSV="/home/ga/Documents/exports/fraud_audit.csv"
DB_CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check CSV Output
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE=0

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$OUTPUT_CSV" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check DBeaver Connection State
# Look for "ChinookFraud" in data-sources.json
CONNECTION_FOUND="false"
if [ -f "$DB_CONFIG_DIR/data-sources.json" ]; then
    if grep -qi "ChinookFraud" "$DB_CONFIG_DIR/data-sources.json"; then
        CONNECTION_FOUND="true"
    fi
fi

# 4. Check if DBeaver is still running
APP_RUNNING=$(pgrep -f "dbeaver" > /dev/null && echo "true" || echo "false")

# 5. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_TIME,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    "dbeaver_connection_found": $CONNECTION_FOUND,
    "app_running": $APP_RUNNING,
    "csv_path": "$OUTPUT_CSV"
}
EOF

# Move result to readable location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json