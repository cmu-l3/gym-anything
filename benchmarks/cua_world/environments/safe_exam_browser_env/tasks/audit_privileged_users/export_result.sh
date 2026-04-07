#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting audit_privileged_users results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

# 1. Gather ground truth from the SEB Server database
# We join user and user_role tables to get complete user data
query = """
SELECT u.username, u.name, u.surname, r.user_role 
FROM user u 
LEFT JOIN user_role r ON u.id = r.user_id
"""
users_raw = db_query(query)

db_users = []
if users_raw:
    for line in users_raw.split('\n'):
        if not line.strip(): continue
        parts = line.split('\t')
        if len(parts) >= 4:
            username = parts[0].strip()
            first_name = parts[1].strip() if parts[1] != 'NULL' else ''
            surname = parts[2].strip() if parts[2] != 'NULL' else ''
            role = parts[3].strip() if parts[3] != 'NULL' else ''
            
            full_name = f"{first_name} {surname}".strip()
            db_users.append({
                "username": username,
                "full_name": full_name,
                "role": role
            })

# 2. Check the expected output file
output_path = "/home/ga/Documents/admin_audit.json"
output_exists = os.path.exists(output_path)
output_mtime = os.path.getmtime(output_path) if output_exists else 0
file_created_during_task = output_exists and (output_mtime > start_time)

# 3. Check if Firefox was running at the end
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'task_start': start_time,
    'task_end': time.time(),
    'db_users_ground_truth': db_users,
    'output_exists': output_exists,
    'output_mtime': output_mtime,
    'file_created_during_task': file_created_during_task,
    'agent_output_path': output_path,
    'firefox_running': firefox_running
}

# Write results for verifier to read
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="