#!/bin/bash
# export_result.sh - Post-task export for create_fleet_monitoring_views

echo "=== Exporting create_fleet_monitoring_views result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final State
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
DB_PATH="/opt/aerobridge/aerobridge.sqlite3"

# 2. Check Files
SQL_FILE="/home/ga/Documents/dashboard_views.sql"
DATA_FILE="/home/ga/Documents/dashboard_views_output.txt"

SQL_FILE_EXISTS="false"
SQL_FILE_MTIME="0"
if [ -f "$SQL_FILE" ]; then
    SQL_FILE_EXISTS="true"
    SQL_FILE_MTIME=$(stat -c %Y "$SQL_FILE")
fi

DATA_FILE_EXISTS="false"
DATA_FILE_MTIME="0"
if [ -f "$DATA_FILE" ]; then
    DATA_FILE_EXISTS="true"
    DATA_FILE_MTIME=$(stat -c %Y "$DATA_FILE")
fi

# 3. Inspect Database Views
# We will create a JSON object with details about each view
VIEW_DETAILS="{}"

# Helper to get view info
check_view() {
    local view_name="$1"
    local exists="false"
    local sql=""
    local row_count="0"
    local columns="[]"
    
    # Check existence
    if sqlite3 "$DB_PATH" "SELECT 1 FROM sqlite_master WHERE type='view' AND name='$view_name';" | grep -q 1; then
        exists="true"
        # Get SQL definition (base64 encode to handle special chars safely in JSON)
        sql=$(sqlite3 "$DB_PATH" "SELECT sql FROM sqlite_master WHERE type='view' AND name='$view_name';" | base64 -w 0)
        
        # Try to count rows (if valid)
        row_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $view_name;" 2>/dev/null || echo "-1")
        
        # Get columns (if valid)
        # pragma table_info returns: cid|name|type|notnull|dflt_value|pk
        # We just want names
        cols=$(sqlite3 "$DB_PATH" "PRAGMA table_info($view_name);" 2>/dev/null | cut -d'|' -f2)
        # Convert newline separated to JSON array
        columns=$(echo "$cols" | jq -R . | jq -s .)
    fi
    
    echo "\"$view_name\": { \"exists\": $exists, \"sql_b64\": \"$sql\", \"row_count\": $row_count, \"columns\": ${columns:-[]} }"
}

VIEW1_JSON=$(check_view "v_fleet_overview")
VIEW2_JSON=$(check_view "v_operator_fleet_size")
VIEW3_JSON=$(check_view "v_personnel_directory")

# 4. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "sql_file": {
            "exists": $SQL_FILE_EXISTS,
            "mtime": $SQL_FILE_MTIME
        },
        "data_file": {
            "exists": $DATA_FILE_EXISTS,
            "mtime": $DATA_FILE_MTIME,
            "size": $(stat -c %s "$DATA_FILE" 2>/dev/null || echo "0")
        }
    },
    "views": {
        $VIEW1_JSON,
        $VIEW2_JSON,
        $VIEW3_JSON
    }
}
EOF

# 5. Save result to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="