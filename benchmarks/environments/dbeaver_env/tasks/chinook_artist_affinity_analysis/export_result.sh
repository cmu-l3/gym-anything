#!/bin/bash
# Export script for chinook_artist_affinity_analysis
# Gathers file artifacts, screenshots, and DBeaver state

echo "=== Exporting Artist Affinity Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_CSV="/home/ga/Documents/exports/artist_affinity_pairs.csv"
OUTPUT_SQL="/home/ga/Documents/scripts/affinity_query.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check DBeaver Connection 'Chinook'
# We check the DBeaver data-sources.json configuration
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONNECTION_EXISTS="false"
CONNECTION_NAME_MATCH="false"

if [ -f "$CONFIG_FILE" ]; then
    # Simple grep check first, python parsing in verifier is safer but this provides quick feedback log
    if grep -q "chinook.db" "$CONFIG_FILE"; then
        CONNECTION_EXISTS="true"
    fi
    # Check for exact name "Chinook"
    if grep -q "\"name\": \"Chinook\"" "$CONFIG_FILE"; then
        CONNECTION_NAME_MATCH="true"
    fi
fi

# 3. Check CSV Output
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$OUTPUT_CSV")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_CSV")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check SQL Script
SQL_EXISTS="false"
if [ -f "$OUTPUT_SQL" ]; then
    SQL_EXISTS="true"
fi

# 5. Check if DBeaver is running
APP_RUNNING=$(is_dbeaver_running)

# 6. Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "connection_exists": $CONNECTION_EXISTS,
    "connection_name_match": $CONNECTION_NAME_MATCH,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_path": "$OUTPUT_CSV",
    "sql_exists": $SQL_EXISTS,
    "sql_path": "$OUTPUT_SQL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json