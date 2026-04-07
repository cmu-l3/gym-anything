#!/bin/bash
echo "=== Exporting configure_proctoring_features results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot for VLM and manual review
take_screenshot /tmp/final_screenshot.png

# Safely extract configuration via Python
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

config_exists = False
config_values = {}

# Locate the created exam configuration
node_id = db_query("SELECT id FROM configuration_node WHERE name='Distance Learning 101' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

if node_id:
    config_exists = True
    # Get the active/latest configuration payload linked to the node
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")

    if config_id:
        # Extract all configuration attributes mapped to this specific config
        raw_attrs = db_query(f"SELECT ca.name, cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_id = {config_id}")
        if raw_attrs:
            for line in raw_attrs.split('\n'):
                if '\t' in line:
                    k, v = line.split('\t', 1)
                    config_values[k.strip()] = v.strip()

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'config_exists': config_exists,
    'config_values': config_values,
    'firefox_running': firefox_running,
    'screenshot_path': '/tmp/final_screenshot.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported successfully to /tmp/task_result.json.")
PYEOF

echo "=== Export complete ==="