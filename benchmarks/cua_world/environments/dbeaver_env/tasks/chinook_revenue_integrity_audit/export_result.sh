#!/bin/bash
# Export script for chinook_revenue_integrity_audit
# Collects evidence: CSV output, SQL script, connection status, screenshots

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
CSV_PATH="/home/ga/Documents/exports/invoice_discrepancies.csv"
SQL_PATH="/home/ga/Documents/scripts/audit_query.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Check if CSV exists and was created during task
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING_TASK="false"
CSV_ROW_COUNT=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Count rows (excluding header)
    CSV_ROW_COUNT=$(count_csv_lines "$CSV_PATH")
fi

# 2. Check if SQL script exists
SQL_EXISTS="false"
SQL_SIZE=0
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$SQL_PATH" 2>/dev/null || echo "0")
fi

# 3. Check for DBeaver Connection 'ChinookAudit'
CONNECTION_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple grep check for the connection name in the config file
    if grep -q "ChinookAudit" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND="true"
    fi
fi

# 4. Check if DBeaver is running
APP_RUNNING=$(is_dbeaver_running)

# 5. Capture final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 6. Create JSON payload
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_path": "$CSV_PATH",
    "csv_size_bytes": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_row_count": $CSV_ROW_COUNT,
    "sql_script_exists": $SQL_EXISTS,
    "sql_script_size": $SQL_SIZE,
    "connection_found": $CONNECTION_FOUND,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "task_start_time": $TASK_START,
    "export_time": $CURRENT_TIME
}
EOF

# Move to final location (accessible by copy_from_env)
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="