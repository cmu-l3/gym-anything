#!/bin/bash
set -e
echo "=== Exporting Reconciliation Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/exports/reconciliation_report.csv"
SQL_PATH="/home/ga/Documents/scripts/reconciliation.sql"
GT_FILE="/tmp/reconciliation_ground_truth.json"
DBEAVER_CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Check 1: CSV Report ---
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_DATA="{}"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Parse CSV into JSON using Python
    CSV_DATA=$(python3 -c "
import csv, json
try:
    rows = []
    with open('$CSV_PATH', 'r') as f:
        # Detect dialect (delimiter)
        content = f.read()
        f.seek(0)
        dialect = csv.Sniffer().sniff(content)
        reader = csv.DictReader(f, dialect=dialect)
        
        # Normalize headers to lowercase
        reader.fieldnames = [h.lower().strip() for h in reader.fieldnames]
        
        for row in reader:
            # Clean values
            clean_row = {k: v.strip() for k, v in row.items() if k}
            rows.append(clean_row)
    print(json.dumps(rows))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo "[]")
fi

# --- Check 2: SQL Script ---
SQL_EXISTS="false"
SQL_CONTENT_VALID="false"

if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
    # Basic check for key SQL commands
    if grep -iq "ATTACH" "$SQL_PATH" && \
       (grep -iq "SELECT" "$SQL_PATH" || grep -iq "COUNT" "$SQL_PATH"); then
        SQL_CONTENT_VALID="true"
    fi
fi

# --- Check 3: DBeaver Connection ---
CONNECTION_FOUND="false"
CONNECTION_DETAILS="{}"

if [ -f "$DBEAVER_CONFIG_DIR/data-sources.json" ]; then
    CONNECTION_DETAILS=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG_DIR/data-sources.json', 'r') as f:
        data = json.load(f)
    
    found = False
    details = {}
    
    # Iterate over connections
    for cid, conn in data.get('connections', {}).items():
        name = conn.get('name', '')
        if 'chinookprod' in name.lower().replace(' ', ''):
            found = True
            details = {
                'name': name,
                'path': conn.get('configuration', {}).get('database', ''),
                'type': conn.get('provider', '')
            }
            break
            
    print(json.dumps({'found': found, 'details': details}))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null)
    
    if echo "$CONNECTION_DETAILS" | grep -q '"found": true'; then
        CONNECTION_FOUND="true"
    fi
fi

# Load Ground Truth
GROUND_TRUTH="{}"
if [ -f "$GT_FILE" ]; then
    GROUND_TRUTH=$(cat "$GT_FILE")
fi

# Assemble Result JSON
# Using a temp file to avoid quoting issues
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_data": $CSV_DATA,
    "sql_exists": $SQL_EXISTS,
    "sql_valid": $SQL_CONTENT_VALID,
    "connection_found": $CONNECTION_FOUND,
    "connection_details": $CONNECTION_DETAILS,
    "ground_truth": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="