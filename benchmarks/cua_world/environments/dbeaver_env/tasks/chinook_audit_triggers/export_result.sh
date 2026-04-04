#!/bin/bash
# Export script for chinook_audit_triggers task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

TARGET_DB="/home/ga/Documents/databases/chinook_triggers.db"
EXPORT_CSV="/home/ga/Documents/exports/audit_log.csv"
SCRIPT_SQL="/home/ga/Documents/scripts/audit_triggers.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check DBeaver Connection
CONNECTION_FOUND="false"
CONNECTION_EXACT_MATCH="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    CONN_CHECK=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    found = False
    exact = False
    for k, v in config.get('connections', {}).items():
        name = v.get('name', '')
        db_path = v.get('configuration', {}).get('database', '')
        if 'chinook_triggers.db' in db_path:
            found = True
            if name == 'ChinookTriggers':
                exact = True
    print(f'{found}|{exact}')
except Exception as e:
    print('False|False')
" 2>/dev/null)
    
    CONNECTION_FOUND=$(echo "$CONN_CHECK" | cut -d'|' -f1)
    CONNECTION_EXACT_MATCH=$(echo "$CONN_CHECK" | cut -d'|' -f2)
fi

# 2. Check Database Schema (Audit Table & Triggers)
AUDIT_TABLE_EXISTS="false"
TRIGGER_COUNT=0
TRIGGER_NAMES=""

if [ -f "$TARGET_DB" ]; then
    # Check audit_log table
    if sqlite3 "$TARGET_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log'" | grep -q "audit_log"; then
        AUDIT_TABLE_EXISTS="true"
    fi
    
    # Check triggers
    TRIGGER_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND tbl_name='customers'")
    TRIGGER_NAMES=$(sqlite3 "$TARGET_DB" "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='customers'" | tr '\n' ',')
fi

# 3. Check Data State (Customers & Audit Log Content)
CUSTOMER_1_EMAIL=""
CUSTOMER_60_EXISTS="false"
AUDIT_LOG_ROWS="[]"
AUDIT_LOG_COUNT=0

if [ "$AUDIT_TABLE_EXISTS" = "true" ]; then
    # Get Customer 1 Email
    CUSTOMER_1_EMAIL=$(sqlite3 "$TARGET_DB" "SELECT Email FROM customers WHERE CustomerId=1" 2>/dev/null || echo "")
    
    # Check Customer 60
    COUNT_60=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE CustomerId=60" 2>/dev/null || echo "0")
    if [ "$COUNT_60" -gt "0" ]; then
        CUSTOMER_60_EXISTS="true"
    fi
    
    # Get Audit Log Content (dump as JSON for verification)
    AUDIT_LOG_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM audit_log" 2>/dev/null || echo "0")
    
    # Simple JSON construction of the audit log data
    AUDIT_LOG_ROWS=$(sqlite3 "$TARGET_DB" "SELECT json_object('operation', operation, 'record_id', record_id, 'old_values', old_values, 'new_values', new_values) FROM audit_log" | jq -s '.' 2>/dev/null || echo "[]")
fi

# 4. Check Files (CSV Export & SQL Script)
CSV_EXISTS="false"
CSV_SIZE=0
SQL_EXISTS="false"
SQL_SIZE=0

if [ -f "$EXPORT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$EXPORT_CSV" 2>/dev/null || echo "0")
fi

if [ -f "$SCRIPT_SQL" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$SCRIPT_SQL" 2>/dev/null || echo "0")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "connection_found": $([ "$CONNECTION_FOUND" = "True" ] && echo "true" || echo "false"),
    "connection_exact_name": $([ "$CONNECTION_EXACT_MATCH" = "True" ] && echo "true" || echo "false"),
    "audit_table_exists": $AUDIT_TABLE_EXISTS,
    "trigger_count": $TRIGGER_COUNT,
    "trigger_names": "$TRIGGER_NAMES",
    "customer_1_email": "$CUSTOMER_1_EMAIL",
    "customer_60_exists": $CUSTOMER_60_EXISTS,
    "audit_log_count": $AUDIT_LOG_COUNT,
    "audit_log_data": $AUDIT_LOG_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "sql_exists": $SQL_EXISTS,
    "sql_size": $SQL_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="