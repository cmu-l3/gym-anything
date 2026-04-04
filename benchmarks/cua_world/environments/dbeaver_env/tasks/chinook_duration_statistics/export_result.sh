#!/bin/bash
# Export script for chinook_duration_statistics task

echo "=== Exporting Chinook Duration Statistics Result ==="

source /workspace/scripts/task_utils.sh

# Paths
STATS_CSV="/home/ga/Documents/exports/genre_duration_stats.csv"
OUTLIERS_CSV="/home/ga/Documents/exports/duration_outliers.csv"
SQL_SCRIPT="/home/ga/Documents/exports/duration_stats.sql" # Agent might save here
SQL_SCRIPT_ALT="/home/ga/Documents/scripts/duration_stats.sql" # Or here per instructions
DB_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check DBeaver Connection
CONNECTION_EXISTS="false"
if [ -f "$DB_CONFIG" ]; then
    if grep -q "Chinook" "$DB_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# 2. Check Stats CSV
STATS_CSV_EXISTS="false"
STATS_ROW_COUNT=0
if [ -f "$STATS_CSV" ]; then
    STATS_CSV_EXISTS="true"
    # Count rows excluding header
    STATS_ROW_COUNT=$(($(wc -l < "$STATS_CSV") - 1))
fi

# 3. Check Outliers CSV
OUTLIERS_CSV_EXISTS="false"
OUTLIERS_ROW_COUNT=0
if [ -f "$OUTLIERS_CSV" ]; then
    OUTLIERS_CSV_EXISTS="true"
    OUTLIERS_ROW_COUNT=$(($(wc -l < "$OUTLIERS_CSV") - 1))
fi

# 4. Check SQL Script
SQL_EXISTS="false"
if [ -f "$SQL_SCRIPT" ]; then
    SQL_EXISTS="true"
    SQL_PATH="$SQL_SCRIPT"
elif [ -f "$SQL_SCRIPT_ALT" ]; then
    SQL_EXISTS="true"
    SQL_PATH="$SQL_SCRIPT_ALT"
fi

# 5. Check Timestamps (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_CREATED_DURING_TASK="false"

STATS_TIME=$(stat -c %Y "$STATS_CSV" 2>/dev/null || echo "0")
OUTLIERS_TIME=$(stat -c %Y "$OUTLIERS_CSV" 2>/dev/null || echo "0")

if [ "$STATS_TIME" -gt "$TASK_START" ] && [ "$OUTLIERS_TIME" -gt "$TASK_START" ]; then
    FILES_CREATED_DURING_TASK="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "stats_csv_exists": $STATS_CSV_EXISTS,
    "stats_row_count": $STATS_ROW_COUNT,
    "outliers_csv_exists": $OUTLIERS_CSV_EXISTS,
    "outliers_row_count": $OUTLIERS_ROW_COUNT,
    "sql_script_exists": $SQL_EXISTS,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "stats_csv_path": "$STATS_CSV",
    "outliers_csv_path": "$OUTLIERS_CSV"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# Prepare files for verification (make copies to safe location)
cp /tmp/chinook_stats_ground_truth.json /tmp/ground_truth.json 2>/dev/null || true
if [ "$STATS_CSV_EXISTS" = "true" ]; then
    cp "$STATS_CSV" /tmp/agent_stats.csv
fi
if [ "$OUTLIERS_CSV_EXISTS" = "true" ]; then
    cp "$OUTLIERS_CSV" /tmp/agent_outliers.csv
fi

echo "=== Export Complete ==="