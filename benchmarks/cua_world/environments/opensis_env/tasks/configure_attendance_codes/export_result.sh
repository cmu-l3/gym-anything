#!/bin/bash
echo "=== Exporting Configure Attendance Codes Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get verification data
SYEAR=$(cat /tmp/target_syear.txt 2>/dev/null || echo "2025")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the specific new codes
# We export result as a Python script to robustly generate JSON
# This avoids bash string escaping hell with JSON

python3 -c "
import json
import subprocess
import sys

def run_query(query):
    cmd = ['mysql', '-u', 'opensis_user', '-popensis_password_123', 'opensis', '-N', '-B', '-e', query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return result
    except Exception:
        return ''

syear = '$SYEAR'
initial_count = int('$INITIAL_COUNT')

# Check 'Half Day' (HD)
hd_query = f\"SELECT id, title, short_name, type, state_code FROM attendance_codes WHERE short_name='HD' AND school_id=1 AND syear='{syear}'\"
hd_raw = run_query(hd_query)
hd_exists = bool(hd_raw)
hd_data = {}
if hd_exists:
    parts = hd_raw.split('\t')
    if len(parts) >= 5:
        hd_data = {
            'id': parts[0],
            'title': parts[1],
            'short_name': parts[2],
            'type': parts[3],
            'state_code': parts[4]
        }

# Check 'Virtual Attendance' (VA)
va_query = f\"SELECT id, title, short_name, type, state_code FROM attendance_codes WHERE short_name='VA' AND school_id=1 AND syear='{syear}'\"
va_raw = run_query(va_query)
va_exists = bool(va_raw)
va_data = {}
if va_exists:
    parts = va_raw.split('\t')
    if len(parts) >= 5:
        va_data = {
            'id': parts[0],
            'title': parts[1],
            'short_name': parts[2],
            'type': parts[3],
            'state_code': parts[4]
        }

# Check total count
count_query = f\"SELECT COUNT(*) FROM attendance_codes WHERE school_id=1 AND syear='{syear}'\"
final_count_raw = run_query(count_query)
final_count = int(final_count_raw) if final_count_raw.isdigit() else 0

result = {
    'initial_count': initial_count,
    'final_count': final_count,
    'count_increase': final_count - initial_count,
    'hd_code': {
        'exists': hd_exists,
        'data': hd_data
    },
    'va_code': {
        'exists': va_exists,
        'data': va_data
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Exported JSON result.')
"

# Set permissions so the host can read it (if using volume mounts)
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="