#!/bin/bash
# Export script for schedule_patient_recall
# Dumps recent database changes to verify the EMR recorded the recall

echo "=== Exporting schedule_patient_recall Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Run Python script to scan the FreeMED database for the newly created recall
# This approach dynamically scans all tables since FreeMED module table names can vary
cat > /tmp/db_scanner.py << 'EOF'
import json
import datetime

def default_converter(o):
    if isinstance(o, (datetime.date, datetime.datetime)):
        return o.isoformat()
    return str(o)

result = {"success": False, "records": [], "patient_id": None}

try:
    try:
        import pymysql
        conn = pymysql.connect(host='localhost', user='freemed', password='freemed', database='freemed')
        cursor = conn.cursor(pymysql.cursors.DictCursor)
    except ImportError:
        import mysql.connector
        conn = mysql.connector.connect(host='localhost', user='freemed', password='freemed', database='freemed')
        cursor = conn.cursor(dictionary=True)

    # Get patient ID
    cursor.execute("SELECT id FROM patient WHERE ptfname='Thomas' AND ptlname='Vance' LIMIT 1")
    pt = cursor.fetchone()
    if pt:
        result["patient_id"] = str(pt['id'])
    
    # Check all tables for recent records
    cursor.execute("SHOW TABLES")
    tables = [list(r.values())[0] for r in cursor.fetchall()]
    
    for t in tables:
        # Skip static/unrelated high-volume tables
        if t in ['user', 'patient', 'config', 'log', 'audit']: 
            continue
            
        try:
            # Grab the 20 most recent records from each table to look for our recall
            query = f"SELECT * FROM `{t}` ORDER BY id DESC LIMIT 20"
            cursor.execute(query)
            rows = cursor.fetchall()
            for row in rows:
                row['_table'] = t
                result["records"].append(row)
        except Exception as e:
            pass # Table might not have an 'id' column, skip

    result["success"] = True

except Exception as e:
    result["error"] = str(e)

# Write output to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, default=default_converter)
EOF

echo "Scanning FreeMED database for records..."
python3 /tmp/db_scanner.py

# Ensure permissions are open for the verifier to read
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Database scan complete. Results saved to /tmp/task_result.json."
echo "=== Export Complete ==="