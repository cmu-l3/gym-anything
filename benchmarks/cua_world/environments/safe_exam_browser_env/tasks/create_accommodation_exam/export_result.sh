#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting create_accommodation_exam results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_exam_count.txt 2>/dev/null || echo "0")

# Use a Python script to robustly export tables bypassing schema variations
python3 << PYEOF
import json
import time
import subprocess
import os

def get_table_as_dicts(table_name):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '--batch', '-e', f"SELECT * FROM {table_name}"],
        capture_output=True, text=True
    )
    lines = result.stdout.strip().split('\n')
    if not lines or not lines[0]: return []
    headers = lines[0].split('\t')
    data = []
    for line in lines[1:]:
        values = line.split('\t')
        row = dict(zip(headers, values))
        data.append(row)
    return data

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True
    )
    return result.stdout.strip()

start_time = float($START_TIME)
initial_count = int($INITIAL_COUNT)
current_count = int(db_query("SELECT COUNT(*) FROM exam") or 0)

exams = get_table_as_dicts('exam')
configs = get_table_as_dicts('configuration_node')

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'initial_exam_count': initial_count,
    'current_exam_count': current_count,
    'exams': exams,
    'configs': configs,
    'firefox_running': firefox_running,
    'screenshot_path': '/tmp/final_screenshot.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported DB state successfully.")
PYEOF

echo "=== Export complete ==="