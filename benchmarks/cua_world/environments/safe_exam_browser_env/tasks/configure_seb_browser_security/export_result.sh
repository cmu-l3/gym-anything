#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_seb_browser_security results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Extract the configuration settings directly from the MariaDB database
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

start_time = float(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

# Verify if the configuration exists
config_exists = False
settings = {}

node_id = db_query("SELECT id FROM configuration_node WHERE name='LPN Certification Practice Exam' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

if node_id:
    config_exists = True
    # Find the linked configuration ID
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} LIMIT 1")
    
    if config_id:
        # Extract all configuration attributes and their values for this config
        query = f"""
        SELECT ca.name, cv.value
        FROM configuration_value cv
        JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id
        WHERE cv.configuration_id = {config_id}
        """
        
        raw_values = db_query(query)
        if raw_values:
            for line in raw_values.split('\n'):
                if '\t' in line:
                    attr, val = line.split('\t', 1)
                    settings[attr] = val

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'config_exists': config_exists,
    'settings': settings,
    'firefox_running': firefox_running
}

with open('/tmp/configure_seb_browser_security_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="