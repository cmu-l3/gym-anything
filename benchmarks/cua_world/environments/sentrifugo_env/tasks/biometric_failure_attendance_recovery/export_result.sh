#!/bin/bash
echo "=== Exporting biometric_failure_attendance_recovery result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# We use a robust Python script to dump all attendance/time related tables
# and the user IDs. This prevents verification failures if the exact table name
# differs slightly from expectations (e.g. main_attendance vs main_time_attendance).
python3 << EOF
import json
import subprocess
import os

def run_query(query):
    try:
        cmd = ['docker', 'exec', 'sentrifugo-db', 'mysql', '-u', 'root', '-prootpass123', 'sentrifugo', '-N', '-e', query]
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return output.decode('utf-8').strip().split('\n')
    except Exception as e:
        return []

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "uids": {},
    "db_rows": []
}

# 1. Get UIDs for the three employees
for empid in ['EMP018', 'EMP019', 'EMP020']:
    rows = run_query(f"SELECT id FROM main_users WHERE employeeId='{empid}';")
    if rows and rows[0]:
        result['uids'][empid] = rows[0].strip()

# 2. Find any tables related to attendance or time
tables = run_query("SELECT table_name FROM information_schema.tables WHERE table_schema='sentrifugo' AND (table_name LIKE '%attend%' OR table_name LIKE '%time%');")

# 3. Dump all rows from these tables to search for our inputs
all_rows = []
for t in tables:
    t = t.strip()
    if not t: continue
    
    # We dump all rows. In a real system this might be large, but Sentrifugo seed data is small.
    # To be safe, we only dump rows containing our target date or UIDs if possible,
    # but a full dump is safest for robust string matching.
    rows = run_query(f"SELECT * FROM {t};")
    for r in rows:
        if r.strip():
            all_rows.append(r.strip())

result['db_rows'] = all_rows

# Write to file securely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Ensure correct permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"