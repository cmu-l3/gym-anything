#!/bin/bash
set -e
echo "=== Exporting add_new_school result ==="

# 1. Take final screenshot (Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_IDS=$(cat /tmp/initial_school_ids.txt 2>/dev/null || echo "")

# 3. Query Database for the Target School
# We look for the most recently created school that matches the name
echo "Querying database..."

# Helper to run mysql query and output JSON-compatible string or null
query_school() {
    mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e \
    "SELECT id, title, address, city, state, zipcode, phone, created_date 
     FROM schools 
     WHERE title LIKE '%Riverside%' 
     ORDER BY id DESC LIMIT 1" 2>/dev/null
}

SCHOOL_DATA=$(query_school)

# 4. Construct JSON Result
# We use python to safely construct JSON to handle potential special chars in DB output
python3 -c "
import json
import sys
import os

try:
    school_line = '''$SCHOOL_DATA'''
    initial_ids_str = '''$INITIAL_IDS'''
    
    result = {
        'found': False,
        'school': {},
        'is_new_record': False,
        'task_timestamp': $TASK_START
    }

    if school_line.strip():
        parts = school_line.strip().split('\t')
        if len(parts) >= 7:
            # Map columns to keys
            school_record = {
                'id': parts[0],
                'title': parts[1],
                'address': parts[2],
                'city': parts[3],
                'state': parts[4],
                'zipcode': parts[5],
                'phone': parts[6]
            }
            result['school'] = school_record
            result['found'] = True
            
            # Anti-gaming: Check if ID is not in initial list
            initial_ids = [x.strip() for x in initial_ids_str.split(',') if x.strip()]
            if school_record['id'] not in initial_ids:
                result['is_new_record'] = True

    # Write to temp file
    with open('/tmp/temp_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f'Error constructing JSON: {e}', file=sys.stderr)
"

# 5. Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm /tmp/temp_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json