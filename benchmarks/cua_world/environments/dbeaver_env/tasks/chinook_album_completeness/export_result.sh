#!/bin/bash
# Export script for chinook_album_completeness task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_CSV="/home/ga/Documents/exports/album_sales_analysis.csv"
OUTPUT_SQL="/home/ga/Documents/scripts/album_analysis.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ------------------------------------------------------------------
# CHECK ARTIFACTS
# ------------------------------------------------------------------

# Check CSV
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$OUTPUT_CSV")
    CSV_MTIME=$(stat -c%Y "$OUTPUT_CSV")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Check SQL
SQL_EXISTS="false"
SQL_SIZE=0
if [ -f "$OUTPUT_SQL" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$OUTPUT_SQL")
fi

# Check DBeaver Connection
CONNECTION_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple grep check for the connection name
    if grep -q "\"name\": \"Chinook\"" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND="true"
    fi
fi

# Check App State
APP_RUNNING=$(pgrep -f "dbeaver" > /dev/null && echo "true" || echo "false")

# ------------------------------------------------------------------
# PREPARE RESULT JSON
# ------------------------------------------------------------------

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_path": "$OUTPUT_CSV",
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "sql_exists": $SQL_EXISTS,
    "sql_path": "$OUTPUT_SQL",
    "connection_found": $CONNECTION_FOUND,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result summary saved to /tmp/task_result.json"
echo "=== Export Complete ==="