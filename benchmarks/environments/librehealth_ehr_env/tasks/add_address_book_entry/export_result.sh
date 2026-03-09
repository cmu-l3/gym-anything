#!/bin/bash
echo "=== Exporting Add Address Book Entry Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get the Initial Max ID recorded during setup
INITIAL_MAX_ID=$(cat /tmp/initial_max_user_id.txt 2>/dev/null || echo "999999999")

# 3. Query the database for the created entry
# We select relevant fields to verify against the task description.
# We explicitly check for fname='Elena' and lname='Rodriguez'.
# Note: In LibreHealth/OpenEMR, address book entries are often stored in the 'users' table 
# with specific flags or just as users without login permissions.

echo "Querying database for Elena Rodriguez..."

# Construct a JSON object using python to safely handle SQL output and escaping
# We query the row that matches the name AND has an ID > Initial Max ID (created during this session)
python3 -c "
import json
import subprocess
import sys

def run_query(sql):
    try:
        # Use the utility script wrapper for docker exec
        cmd = ['librehealth-query', sql]
        result = subprocess.check_output(cmd).decode('utf-8').strip()
        return result
    except Exception as e:
        return ''

# Get columns for the specific user
# We fetch the most recently added 'Elena Rodriguez'
sql = \"SELECT id, fname, lname, organization, specialty, phone, fax, email, street, city, state, zip, abook_type, notes FROM users WHERE fname='Elena' AND lname='Rodriguez' ORDER BY id DESC LIMIT 1\"

row_str = run_query(sql)

result_data = {
    'found': False,
    'data': {},
    'initial_max_id': int('$INITIAL_MAX_ID')
}

if row_str:
    # librehealth-query returns tab-separated values
    # Columns: id, fname, lname, organization, specialty, phone, fax, email, street, city, state, zip, abook_type, notes
    parts = row_str.split('\t')
    if len(parts) >= 12:
        result_data['found'] = True
        result_data['data'] = {
            'id': int(parts[0]) if parts[0].isdigit() else 0,
            'fname': parts[1],
            'lname': parts[2],
            'organization': parts[3],
            'specialty': parts[4],
            'phone': parts[5],
            'fax': parts[6],
            'email': parts[7],
            'street': parts[8],
            'city': parts[9],
            'state': parts[10],
            'zip': parts[11],
            'abook_type': parts[12] if len(parts) > 12 else '',
            'notes': parts[13] if len(parts) > 13 else ''
        }

# Write to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

print('Exported JSON data.')
"

# 4. Save file permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="