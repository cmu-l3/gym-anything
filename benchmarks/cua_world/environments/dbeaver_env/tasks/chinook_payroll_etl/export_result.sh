#!/bin/bash
# Export script for chinook_payroll_etl task
echo "=== Exporting Chinook Payroll ETL Result ==="

source /workspace/scripts/task_utils.sh

PAYROLL_DB="/home/ga/Documents/databases/payroll.db"
CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
SCRIPT_PATH="/home/ga/Documents/scripts/calculate_commissions.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Payroll DB was modified
PAYROLL_DB_MODIFIED="false"
if [ -f "$PAYROLL_DB" ]; then
    DB_MTIME=$(stat -c %Y "$PAYROLL_DB" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        PAYROLL_DB_MODIFIED="true"
    fi
    DB_SIZE=$(stat -c %s "$PAYROLL_DB" 2>/dev/null || echo "0")
else
    DB_SIZE=0
fi

# 2. Check if Script exists
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# 3. Analyze Payroll DB Content (Agent Results)
echo "Analyzing Agent Results..."
AGENT_RESULTS="[]"
TABLE_EXISTS="false"
COLUMNS_VALID="false"

if [ -f "$PAYROLL_DB" ] && [ "$DB_SIZE" -gt 0 ]; then
    # Check if table exists
    TABLE_CHECK=$(sqlite3 "$PAYROLL_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='commissions_2011';" 2>/dev/null || echo "0")
    
    if [ "$TABLE_CHECK" -eq "1" ]; then
        TABLE_EXISTS="true"
        
        # Check columns
        SCHEMA=$(sqlite3 "$PAYROLL_DB" "PRAGMA table_info(commissions_2011);" 2>/dev/null)
        if echo "$SCHEMA" | grep -qi "EmployeeId" && \
           echo "$SCHEMA" | grep -qi "FullName" && \
           echo "$SCHEMA" | grep -qi "TotalCommission"; then
            COLUMNS_VALID="true"
            
            # Extract data to JSON
            # We use a python one-liner to dump the table to JSON safely handling quotes/types
            AGENT_RESULTS=$(python3 -c "
import sqlite3, json, sys
try:
    conn = sqlite3.connect('$PAYROLL_DB')
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM commissions_2011 ORDER BY EmployeeId')
    rows = [dict(row) for row in cursor.fetchall()]
    print(json.dumps(rows))
except Exception as e:
    print('[]')
")
        fi
    fi
fi

# 4. Calculate Ground Truth (from Chinook DB)
echo "Calculating Ground Truth..."
GROUND_TRUTH=$(python3 -c "
import sqlite3, json
try:
    conn = sqlite3.connect('$CHINOOK_DB')
    cursor = conn.cursor()
    
    query = \"\"\"
    SELECT 
        e.EmployeeId,
        e.FirstName || ' ' || e.LastName as FullName,
        ROUND(SUM(ii.UnitPrice * ii.Quantity * 
            CASE 
                WHEN g.Name = 'Rock' THEN 0.15 
                WHEN g.Name = 'Latin' THEN 0.10 
                ELSE 0.05 
            END), 2) as Commission
    FROM employees e
    JOIN customers c ON e.EmployeeId = c.SupportRepId
    JOIN invoices i ON c.CustomerId = i.CustomerId
    JOIN invoice_items ii ON i.InvoiceId = ii.InvoiceId
    JOIN tracks t ON ii.TrackId = t.TrackId
    JOIN genres g ON t.GenreId = g.GenreId
    WHERE strftime('%Y', i.InvoiceDate) = '2011'
    GROUP BY e.EmployeeId
    ORDER BY e.EmployeeId
    \"\"\"
    
    cursor.execute(query)
    # Convert list of tuples to list of dicts for easier comparison
    results = []
    for row in cursor.fetchall():
        results.append({
            'EmployeeId': row[0],
            'FullName': row[1],
            'TotalCommission': row[2]
        })
    print(json.dumps(results))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# 5. Check DBeaver Connection (via configuration files)
# We look for 'payroll' in the data-sources.json
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
PAYROLL_CONNECTION_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -qi "payroll" "$DBEAVER_CONFIG"; then
        PAYROLL_CONNECTION_FOUND="true"
    fi
fi

# 6. Check if app was running
APP_RUNNING=$(pgrep -f "dbeaver" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "payroll_db_modified": $PAYROLL_DB_MODIFIED,
    "script_exists": $SCRIPT_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "columns_valid": $COLUMNS_VALID,
    "payroll_connection_found": $PAYROLL_CONNECTION_FOUND,
    "agent_data": $AGENT_RESULTS,
    "ground_truth": $GROUND_TRUTH,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="