#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting schedule_and_activate_exam results ==="

take_screenshot /tmp/final_screenshot.png

python3 << 'PYEOF'
import json
import time
import subprocess

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        return None
    val = result.stdout.strip()
    return val if val else None

start_time = float(open('/tmp/task_start_time.txt').read().strip())
exam_name = "CS101 - Algorithms Final"

# Fetch from exam table
exam_id = db_query(f"SELECT id FROM exam WHERE name='{exam_name}' ORDER BY id DESC LIMIT 1")
exam_details = {}
if exam_id:
    for col in ['status', 'active', 'valid_from', 'valid_to', 'start_time', 'end_time', 'enabled', 'published']:
        val = db_query(f"SELECT {col} FROM exam WHERE id={exam_id}")
        if val: exam_details[col] = val

# Fetch from configuration_node (as SEB Server schemas vary, we check both objects)
config_id = db_query(f"SELECT id FROM configuration_node WHERE name='{exam_name}' ORDER BY id DESC LIMIT 1")
config_details = {}
if config_id:
    for col in ['status', 'active', 'valid_from', 'valid_to', 'start_time', 'end_time', 'enabled', 'published']:
        val = db_query(f"SELECT {col} FROM configuration_node WHERE id={config_id}")
        if val: config_details[col] = val

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'exam_id': exam_id,
    'exam_details': exam_details,
    'config_id': config_id,
    'config_details': config_details,
    'firefox_running': firefox_running,
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="