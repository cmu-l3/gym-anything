#!/bin/bash
# Export result script for create_patient_referral task

echo "=== Exporting create_patient_referral result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state evidence
take_screenshot /tmp/task_referral_final.png

# 2. Extract database state dynamically to JSON
python3 -c "
import mysql.connector
import json
import os

try:
    with open('/tmp/ref_table_info.txt', 'r') as f:
        table, initial_count, initial_max_id = f.read().strip().split(',')
except Exception:
    table, initial_count, initial_max_id = 'none', '0', '0'

new_referrals = []
if table != 'none':
    try:
        conn = mysql.connector.connect(user='freemed', password='freemed', database='freemed')
        cursor = conn.cursor(dictionary=True)
        # Fetch only records created during the task
        cursor.execute(f\"SELECT * FROM {table} WHERE id > {initial_max_id}\")
        rows = cursor.fetchall()
        new_referrals = [{k: str(v) for k, v in row.items()} for row in rows]
    except Exception as e:
        print(f'Error querying new referrals: {e}')

def get_id(file_path):
    try:
        with open(file_path, 'r') as f:
            return f.read().strip()
    except:
        return ''

result = {
    'table': table,
    'initial_count': int(initial_count),
    'initial_max_id': int(initial_max_id),
    'new_referrals': new_referrals,
    'patient_id': get_id('/tmp/patient_id'),
    'chen_id': get_id('/tmp/chen_id'),
    'wilson_id': get_id('/tmp/wilson_id'),
    'timestamp': '$(date -Iseconds)',
    'screenshot_path': '/tmp/task_referral_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export Complete."