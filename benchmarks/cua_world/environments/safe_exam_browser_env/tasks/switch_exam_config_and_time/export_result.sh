#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting switch_exam_config_and_time results ==="

take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

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
    return result.stdout.strip()

start_time = float(open('/tmp/task_start_time.txt').read().strip() or "0")

# Fetch Exam Data
exam_data_str = db_query("SELECT configuration_id, enddate FROM exam WHERE name='Intro to Psychology 101' LIMIT 1")

exam_found = False
config_name = ""
end_date_str = ""
config_id = ""

if exam_data_str:
    exam_found = True
    parts = exam_data_str.split('\t')
    if len(parts) >= 2:
        config_id = parts[0]
        end_date_str = parts[1]
        
        # Get config name
        config_name = db_query(f"SELECT name FROM configuration_node WHERE id={config_id}")

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'exam_found': exam_found,
    'config_name': config_name,
    'end_date': end_date_str,
    'firefox_running': firefox_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="