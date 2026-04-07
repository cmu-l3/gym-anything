#!/bin/bash
echo "=== Exporting task results ==="

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Query Database for Final State
# We use -N (skip headers) and -B (batch/tab-separated) for easier parsing, 
# but JSON is safer if we handle it in python or carefully here. 
# We'll use a robust SQL query and format as JSON manually to ensure valid syntax.

echo "Querying final school data..."
DB_RESULT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e \
    "SELECT address, city, state, zipcode, phone FROM schools WHERE id=1 LIMIT 1" 2>/dev/null)

# Parse tab-separated output
# Expected: 456 Oak Avenue    Springfield    IL    62704    217-555-9876
IFS=$'\t' read -r ADDRESS CITY STATE ZIP PHONE <<< "$DB_RESULT"

# 3. Check if Browser is still running
APP_RUNNING=$(pgrep -f "chrome|chromium" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
# We use python to generate the JSON to handle escaping safely
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png',
    'school_data': {
        'address': '''$ADDRESS''',
        'city': '''$CITY''',
        'state': '''$STATE''',
        'zipcode': '''$ZIP''',
        'phone': '''$PHONE'''
    }
}

with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(data, f)
"

# Move to final location with loose permissions so verifier can read it
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="