#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting create_exam_configuration results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

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

start_time = float(open('/tmp/task_start_time.txt').read().strip())

# Load baseline
baseline = {}
try:
    with open('/tmp/seb_task_baseline_create_exam_configuration.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_config_count = baseline.get('exam_config_count', 0)

# Check for new exam configuration named 'CS101 Final Exam Configuration'
config_exists = db_query(
    "SELECT COUNT(*) FROM configuration_node WHERE name='CS101 Final Exam Configuration' AND type='EXAM_CONFIG'"
)
config_exists = int(config_exists) if config_exists else 0

# Get config details if it exists
config_id = ""
config_description = ""
if config_exists > 0:
    config_id = db_query(
        "SELECT id FROM configuration_node WHERE name='CS101 Final Exam Configuration' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1"
    )
    config_description = db_query(
        f"SELECT description FROM configuration_node WHERE id={config_id}"
    ) if config_id else ""

# Count total configs now vs baseline
current_config_count = int(db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'") or 0)
new_configs = current_config_count - baseline_config_count

# Check Firefox is running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'config_exists': config_exists > 0,
    'config_name_match': config_exists > 0,
    'config_id': config_id,
    'config_description': config_description,
    'new_configs_created': new_configs,
    'baseline_config_count': baseline_config_count,
    'current_config_count': current_config_count,
    'firefox_running': firefox_running,
}

with open('/tmp/create_exam_configuration_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
