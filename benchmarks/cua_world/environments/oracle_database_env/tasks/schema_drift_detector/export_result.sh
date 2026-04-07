#!/bin/bash
# Export script for Schema Drift Detector
# Queries the SYSTEM.SCHEMA_DRIFT_LOG table to verify agent findings

source /workspace/scripts/task_utils.sh

echo "=== Exporting Schema Drift Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take screenshot
take_screenshot /tmp/task_final.png

# Check report file
REPORT_FILE="/home/ga/Desktop/drift_report.txt"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE")
    # Check if created during task
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    else
        REPORT_VALID_TIME="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE=0
    REPORT_VALID_TIME="false"
fi

# Query the log table created by the agent
# We export as JSON for the python verifier
echo "Querying SCHEMA_DRIFT_LOG..."

# Use python to safely export SQL result to JSON
python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "table_exists": False,
    "rows": [],
    "row_count": 0,
    "error": None
}

try:
    # Connect as SYSTEM to read the log table
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    # Check if table exists
    cursor.execute("SELECT count(*) FROM dba_tables WHERE owner='SYSTEM' AND table_name='SCHEMA_DRIFT_LOG'")
    exists = cursor.fetchone()[0]
    
    if exists > 0:
        result["table_exists"] = True
        
        # Fetch rows - normalizing column names to lowercase for verification
        cursor.execute("SELECT object_name, drift_type, dev_value, prod_value FROM system.schema_drift_log")
        columns = [col[0].lower() for col in cursor.description]
        
        for row in cursor.fetchall():
            row_dict = {}
            # Map by index since we know the select order
            row_dict["object_name"] = str(row[0]) if row[0] else ""
            row_dict["drift_type"] = str(row[1]) if row[1] else ""
            row_dict["dev_value"] = str(row[2]) if row[2] else ""
            row_dict["prod_value"] = str(row[3]) if row[3] else ""
            result["rows"].append(row_dict)
            
        result["row_count"] = len(result["rows"])
    else:
        result["error"] = "Table SYSTEM.SCHEMA_DRIFT_LOG not found"

except Exception as e:
    result["error"] = str(e)

# Save to file
with open("/tmp/db_log_export.json", "w") as f:
    json.dump(result, f)
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_valid_time": $REPORT_VALID_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Merge DB results into final JSON
python3 -c "
import json
with open('$TEMP_JSON', 'r') as f_main:
    main_data = json.load(f_main)
try:
    with open('/tmp/db_log_export.json', 'r') as f_db:
        db_data = json.load(f_db)
    main_data['db_log'] = db_data
except FileNotFoundError:
    main_data['db_log'] = {'error': 'DB export failed'}

with open('/tmp/task_result.json', 'w') as f_out:
    json.dump(main_data, f_out)
"

# Cleanup
rm "$TEMP_JSON"
rm -f "/tmp/db_log_export.json"
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"