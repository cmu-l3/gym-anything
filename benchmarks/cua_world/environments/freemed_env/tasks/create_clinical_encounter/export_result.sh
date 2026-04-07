#!/bin/bash
echo "=== Exporting create_clinical_encounter task ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual verification
take_screenshot /tmp/task_final.png

# Create a Python script to robustly extract clinical data from MySQL
cat << 'EOF' > /tmp/dump_db.py
import json
import pymysql
import sys
import datetime

# Handle datetime serialization
def default_converter(o):
    if isinstance(o, (datetime.date, datetime.datetime)):
        return o.isoformat()
    return str(o)

result = {
    "pnotes": [],
    "procrec": [],
    "encounters": [],
    "patient_found": False,
    "error": None
}

try:
    # Connect to FreeMED DB
    conn = pymysql.connect(host='localhost', user='freemed', password='freemed', database='freemed', cursorclass=pymysql.cursors.DictCursor)
    with conn.cursor() as cursor:
        # Locate Elena Vasquez
        cursor.execute("SELECT id FROM patient WHERE ptfname='Elena' AND ptlname='Vasquez' LIMIT 1")
        pat = cursor.fetchone()
        
        if pat:
            pat_id = pat['id']
            result['patient_found'] = True
            result['patient_id'] = pat_id

            # Extract Progress Notes (pnotes)
            cursor.execute(f"SELECT * FROM pnotes WHERE patient={pat_id}")
            result['pnotes'] = cursor.fetchall()

            # Extract Procedure Records (procrec)
            cursor.execute(f"SELECT * FROM procrec WHERE patient={pat_id}")
            result['procrec'] = cursor.fetchall()

            # Extract Encounters (if table exists based on version)
            cursor.execute("SHOW TABLES LIKE 'encounter'")
            if cursor.fetchone():
                cursor.execute(f"SELECT * FROM encounter WHERE patient={pat_id}")
                result['encounters'] = cursor.fetchall()

except Exception as e:
    result['error'] = str(e)

# Save securely to JSON
with open('/tmp/db_dump.json', 'w') as f:
    json.dump(result, f, default=default_converter)
EOF

# Execute the extraction script
python3 /tmp/dump_db.py

# Combine metadata and DB dump into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_timestamp 2>/dev/null || echo 0),
    "task_end": $(cat /tmp/task_end_timestamp 2>/dev/null || echo 0),
    "db_data": $(cat /tmp/db_dump.json 2>/dev/null || echo "{}"),
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Safely copy to final destination avoiding permission locks
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="