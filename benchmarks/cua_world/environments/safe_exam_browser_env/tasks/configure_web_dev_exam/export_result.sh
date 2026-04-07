#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_web_dev_exam results ==="

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

# Find the config node ID
config_node_id = db_query("SELECT id FROM configuration_node WHERE name='CS302 Web Technologies' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

settings = {}
config_exists = False

if config_node_id:
    config_exists = True
    # Get the latest configuration version linked to this node
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={config_node_id} ORDER BY version DESC LIMIT 1")
    
    if config_id:
        # Dump all SEB client settings stored for this configuration
        raw_settings = db_query(f"""
        SELECT ca.name, cv.value
        FROM configuration_value cv
        JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id
        WHERE cv.configuration_id = {config_id}
        """)
        
        for line in raw_settings.split('\n'):
            if '\t' in line:
                key, val = line.split('\t', 1)
                settings[key.strip()] = val.strip()

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'config_exists': config_exists,
    'config_node_id': config_node_id,
    'settings': settings,
    'firefox_running': firefox_running,
}

# Write results to temp and copy over safely
with open('/tmp/configure_web_dev_exam_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

os.system('cp /tmp/configure_web_dev_exam_result_temp.json /tmp/configure_web_dev_exam_result.json')
os.system('chmod 666 /tmp/configure_web_dev_exam_result.json')

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="