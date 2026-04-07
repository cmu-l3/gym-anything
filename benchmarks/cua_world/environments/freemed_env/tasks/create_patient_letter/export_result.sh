#!/bin/bash
echo "=== Exporting create_patient_letter task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Use Python to safely extract the database results to JSON
python3 << 'PYEOF'
import pymysql
import json
import os
from datetime import datetime

# Helper to serialize datetimes
def json_serial(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    if hasattr(obj, 'isoformat'):
        return obj.isoformat()
    return str(obj)

result = {
    "success": False,
    "error": None,
    "patient_id": None,
    "initial_count": 0,
    "final_count": 0,
    "new_letters": [],
    "target_table": None
}

try:
    # Read initial state
    try:
        with open('/tmp/initial_letter_count', 'r') as f:
            result['initial_count'] = int(f.read().strip())
        with open('/tmp/initial_max_letter_id', 'r') as f:
            max_id = int(f.read().strip())
        with open('/tmp/letter_table_name', 'r') as f:
            target_table = f.read().strip()
            result['target_table'] = target_table
    except Exception as e:
        max_id = 0
        target_table = 'letter'

    conn = pymysql.connect(host='localhost', user='freemed', password='freemed', db='freemed', cursorclass=pymysql.cursors.DictCursor)
    with conn.cursor() as cursor:
        # Get Patient ID
        cursor.execute("SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1")
        patient_row = cursor.fetchone()
        if patient_row:
            result['patient_id'] = patient_row['id']
            
        # Get new letter count
        cursor.execute(f"SELECT COUNT(*) as count FROM {target_table}")
        result['final_count'] = cursor.fetchone()['count']
        
        # Extract new letters created during task
        cursor.execute(f"SELECT * FROM {target_table} WHERE id > %s", (max_id,))
        result['new_letters'] = cursor.fetchall()
        
    result['success'] = True

except Exception as e:
    result['error'] = str(e)

# Save result safely
temp_path = '/tmp/create_letter_result.tmp.json'
final_path = '/tmp/create_letter_result.json'

with open(temp_path, 'w') as f:
    json.dump(result, f, default=json_serial, indent=2)
    
os.rename(temp_path, final_path)
os.chmod(final_path, 0o666)

print(f"Exported DB results to {final_path}")
PYEOF

echo "Task results extracted:"
cat /tmp/create_letter_result.json
echo "=== Export complete ==="