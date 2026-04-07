#!/bin/bash
echo "=== Exporting add_locker_inventory results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for the specific lockers
# We select ID, number, combination, location, and student_id (to ensure unassigned)
QUERY="SELECT locker_id, locker_number, combination, location, student_id FROM lockers WHERE locker_number IN ('N-100', 'N-101', 'N-102') ORDER BY locker_number ASC"

# Execute query and format as JSON-like structure manually or just raw tab-separated
# Using raw tab-separated is easier to parse in python if we just dump it
RAW_DATA=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "$QUERY" 2>/dev/null || echo "")

# 3. Get Task Metadata (timestamps)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_MAX_ID=$(cat /tmp/initial_max_locker_id.txt 2>/dev/null || echo "0")

# 4. Construct JSON Output
# We will use python to reliably construct the JSON from the raw variables to avoid escaping issues in bash
python3 -c "
import json
import sys
import datetime

try:
    raw_data = '''$RAW_DATA'''
    initial_max_id = int('$INITIAL_MAX_ID')
    
    lockers = []
    for line in raw_data.strip().split('\n'):
        if not line.strip(): continue
        parts = line.split('\t')
        if len(parts) >= 4:
            # Handle potential NULLs for student_id (might be 'NULL' string or empty)
            student_id = parts[4] if len(parts) > 4 else None
            
            lockers.append({
                'locker_id': int(parts[0]),
                'locker_number': parts[1],
                'combination': parts[2],
                'location': parts[3],
                'student_id': student_id
            })

    result = {
        'found_lockers': lockers,
        'initial_max_id': initial_max_id,
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'screenshot_exists': True
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    # Fallback error JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# 5. Fix permissions for verification script to read
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="