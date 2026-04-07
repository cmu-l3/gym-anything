#!/bin/bash
set -e
echo "=== Exporting Configure Enrollment Codes results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_code_count.txt 2>/dev/null || echo "0")

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to query database and generate robust JSON
# This avoids shell string escaping hell
python3 -c "
import json
import subprocess
import time
import sys

def run_query(query):
    cmd = ['mysql', '-u', '$DB_USER', '-p$DB_PASS', '$DB_NAME', '-N', '-B', '-e', query]
    try:
        # Suppress password warning
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        return result
    except Exception as e:
        return ''

try:
    # Get current codes
    # Assuming columns: id, title, short_name, type (or similar)
    # OpenSIS schema often uses 'title', 'short_name', 'type' for enrollment codes
    # We select all columns to be safe and process in python
    
    # First check column names to be safe
    cols = run_query(\"SHOW COLUMNS FROM student_enrollment_codes\")
    col_names = [line.split('\t')[0] for line in cols.strip().split('\n') if line]
    
    # Construct select query
    select_cols = []
    for c in ['id', 'title', 'short_name', 'type']:
        if c in col_names:
            select_cols.append(c)
    
    query = f\"SELECT {','.join(select_cols)} FROM student_enrollment_codes\"
    raw_data = run_query(query)
    
    codes = []
    if raw_data.strip():
        for line in raw_data.strip().split('\n'):
            parts = line.split('\t')
            code_obj = {}
            for i, col in enumerate(select_cols):
                if i < len(parts):
                    code_obj[col] = parts[i]
            codes.append(code_obj)

    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': len(codes),
        'codes': codes,
        'columns_found': select_cols
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    error_res = {'error': str(e), 'codes': []}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(error_res, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="