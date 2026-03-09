#!/bin/bash
echo "=== Exporting Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CSV_PATH="/home/ga/Documents/exports/routing_guide.csv"
SQL_PATH="/home/ga/Documents/scripts/shipping_analysis.sql"
DB_PATH="/home/ga/Documents/databases/northwind.db"

# 1. Check CSV Export
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    FILE_MTIME=$(stat -c %Y "$CSV_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check SQL Script
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 3. Check DBeaver Connection (parse config)
CONNECTION_FOUND="false"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -q "Northwind" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND="true"
    fi
fi

# 4. Check Database View Existence (using sqlite3 directly)
VIEW_EXISTS="false"
if [ -f "$DB_PATH" ]; then
    if sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='view' AND name='v_country_shipper_stats';" | grep -q "1"; then
        VIEW_EXISTS="true"
    fi
fi

# 5. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size": $CSV_SIZE,
    "sql_exists": $SQL_EXISTS,
    "connection_found": $CONNECTION_FOUND,
    "view_exists": $VIEW_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="