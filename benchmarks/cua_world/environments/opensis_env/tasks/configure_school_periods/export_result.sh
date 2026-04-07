#!/bin/bash
echo "=== Exporting configure_school_periods results ==="

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_period_count.txt 2>/dev/null || echo "0")

# 2. Query Database for Final State
# We fetch all periods for school_id 1 to verify correctness
echo "Querying database..."
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Export results as JSON structure using a temporary python script for reliable formatting
# This avoids messy bash string manipulation for JSON
python3 -c "
import json
import subprocess
import sys

def run_query(query):
    cmd = ['mysql', '-u', '$DB_USER', '-p$DB_PASS', '$DB_NAME', '-N', '-B', '-e', query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        return result
    except Exception:
        return ''

# Get periods
query = 'SELECT sort_order, title, short_name, length FROM school_periods WHERE school_id = 1 ORDER BY sort_order'
raw_data = run_query(query)

periods = []
for line in raw_data.strip().split('\n'):
    if not line.strip(): continue
    parts = line.split('\t')
    if len(parts) >= 4:
        periods.append({
            'sort_order': parts[0],
            'title': parts[1],
            'short_name': parts[2],
            'length': parts[3]
        })

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': len(periods),
    'periods': periods
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 3. Take Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Set permissions so the host can read it via copy_from_env (if needed, though usually root works)
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json