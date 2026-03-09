#!/bin/bash
set -e
echo "=== Exporting archive_vip_customers results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

# --- 1. Generate Ground Truth from Source SQLite ---
# We do this inside the container because we have access to the SQLite file here.
# This ensures the verifier compares against the actual data in the environment.
echo "Generating ground truth data..."
python3 -c "
import sqlite3
import json

try:
    conn = sqlite3.connect('/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
    cursor = conn.cursor()
    
    # query to get top 15 customers by spending
    query = \"\"\"
    SELECT 
        c.CustomerId,
        c.FirstName || ' ' || c.LastName as FullName,
        c.Email,
        SUM(i.Total) as TotalSpent
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
    ORDER BY TotalSpent DESC
    LIMIT 15
    \"\"\"
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    result = []
    for row in rows:
        result.append({
            'CustomerId': row[0],
            'FullName': row[1],
            'Email': row[2],
            'TotalSpent': row[3]
        })
    
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    conn.close()
    print(f'Ground truth generated: {len(result)} records')
except Exception as e:
    print(f'Error generating ground truth: {e}')
    # Write empty array on failure
    with open('/tmp/ground_truth.json', 'w') as f:
        f.write('[]')
"

# --- 2. Check ODB File Status ---
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE=0

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi
fi

# --- 3. Check App Status ---
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
fi

# --- 4. Capture Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- 5. Prepare Result JSON ---
# We merge the ground truth directly into the result JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
GROUND_TRUTH_CONTENT=$(cat /tmp/ground_truth.json 2>/dev/null || echo "[]")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth": $GROUND_TRUTH_CONTENT
}
EOF

# Save result with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="