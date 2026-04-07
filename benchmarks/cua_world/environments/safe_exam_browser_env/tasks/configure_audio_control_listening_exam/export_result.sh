#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_audio_control_listening_exam results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception as e:
        return ""

start_time_path = '/tmp/task_start_time.txt'
start_time = float(open(start_time_path).read().strip()) if os.path.exists(start_time_path) else 0.0

# Check for the specific Exam Configuration
config_id = db_query("SELECT id FROM configuration_node WHERE name='Music History Listening Exam' ORDER BY id DESC LIMIT 1")

settings = {}
if config_id:
    # Get all SEB settings for this config
    # Schema: configuration_value -> configuration_attribute -> configuration_node
    query = f"""
    SELECT ca.name, cv.value 
    FROM configuration_value cv 
    JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id 
    WHERE cv.configuration_node_id={config_id}
    """
    raw_settings = db_query(query)
    
    for line in raw_settings.split('\n'):
        if '\t' in line:
            k, v = line.split('\t', 1)
            settings[k] = v

# Check if firefox was running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'config_id': config_id,
    'config_exists': bool(config_id),
    'settings': settings,
    'firefox_running': firefox_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="