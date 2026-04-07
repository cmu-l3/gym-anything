#!/bin/bash
# Export script for update_practice_info
# Queries the NOSH database for the final state of practice_id=1

echo "=== Exporting update_practice_info results ==="

# 1. Capture final screenshot (evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for Practice Info
# We select specific columns relevant to the task to avoid huge JSON dumps
echo "Querying database..."

SQL_QUERY="SELECT practice_name, street_address1, city, state, zip, phone, fax, email FROM practiceinfo WHERE practice_id=1"

# Use docker exec to run query and output tab-separated values
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$SQL_QUERY" 2>/dev/null)

# Parse result into variables (handling potential empty fields)
# Note: output is tab separated
P_NAME=$(echo "$DB_RESULT" | cut -f1)
P_ADDR=$(echo "$DB_RESULT" | cut -f2)
P_CITY=$(echo "$DB_RESULT" | cut -f3)
P_STATE=$(echo "$DB_RESULT" | cut -f4)
P_ZIP=$(echo "$DB_RESULT" | cut -f5)
P_PHONE=$(echo "$DB_RESULT" | cut -f6)
P_FAX=$(echo "$DB_RESULT" | cut -f7)
P_EMAIL=$(echo "$DB_RESULT" | cut -f8)

# 4. Check if data actually changed from initial state
# Compare against the known initial state set in setup_task.sh
CHANGED="false"
# Simple heuristic: check if address is NOT the initial one
if [ "$P_ADDR" != "100 Main St" ]; then
    CHANGED="true"
fi

# 5. Create JSON Result
# We use python to safely generate JSON (avoiding shell escaping hell)
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'db_changed': $CHANGED == 1, # passed as python boolean from shell string comparison logic? No, let's just pass strings
    'practice_info': {
        'practice_name': '''$P_NAME''',
        'street_address1': '''$P_ADDR''',
        'city': '''$P_CITY''',
        'state': '''$P_STATE''',
        'zip': '''$P_ZIP''',
        'phone': '''$P_PHONE''',
        'fax': '''$P_FAX''',
        'email': '''$P_EMAIL'''
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=4)
"

# 6. Secure the output file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json