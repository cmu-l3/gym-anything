#!/bin/bash
set -euo pipefail

echo "=== Exporting seb_server_admin_audit results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to gather DB ground truth and read the report file
python3 << 'PYEOF'
import json
import time
import subprocess
import os

def safe_db_query(query):
    try:
        res = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=15
        )
        return [line for line in res.stdout.strip().split('\n') if line]
    except Exception as e:
        print(f"DB Query failed: {e}")
        return []

start_time = float(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0.0

# 1. Gather Ground Truth from DB
gt = {}

gt['institutions'] = safe_db_query("SELECT name FROM institution")
gt['lms'] = safe_db_query("SELECT name FROM lms_setup")

gt['configs'] = []
config_rows = safe_db_query("SELECT name, status FROM configuration_node WHERE type='EXAM_CONFIG'")
for row in config_rows:
    parts = row.split('\t')
    gt['configs'].append({
        "name": parts[0],
        "status": parts[1] if len(parts) > 1 else "UNKNOWN"
    })

gt['users'] = []
user_rows = safe_db_query("SELECT id, username FROM user")
for row in user_rows:
    parts = row.split('\t')
    if len(parts) >= 2:
        uid, uname = parts[0], parts[1]
        roles = safe_db_query(f"SELECT user_role FROM user_role WHERE user_id={uid}")
        role = roles[0] if roles else "UNKNOWN"
        gt['users'].append({"username": uname, "role": role})

exams = safe_db_query("SELECT name FROM exam")
if not exams:
    exams = safe_db_query("SELECT external_id FROM exam")
gt['exams'] = exams

# 2. Check for the audit report file
possible_paths = [
    "/home/ga/seb_audit_report.txt",
    "/home/ga/Documents/seb_audit_report.txt",
    "/home/ga/Desktop/seb_audit_report.txt"
]

file_content = ""
file_mtime = 0
file_exists = False
actual_path = ""

for path in possible_paths:
    if os.path.exists(path):
        file_exists = True
        actual_path = path
        file_mtime = os.path.getmtime(path)
        try:
            with open(path, 'r', encoding='utf-8') as f:
                file_content = f.read()
        except Exception:
            pass
        break

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'file_exists': file_exists,
    'file_path': actual_path,
    'file_mtime': file_mtime,
    'file_created_during_task': file_mtime > start_time if file_exists else False,
    'file_content': file_content,
    'ground_truth': gt
}

with open('/tmp/seb_server_admin_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic completed.")
PYEOF

# Fix permissions
chmod 666 /tmp/seb_server_admin_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/seb_server_admin_audit_result.json 2>/dev/null || true

echo "=== Export complete ==="