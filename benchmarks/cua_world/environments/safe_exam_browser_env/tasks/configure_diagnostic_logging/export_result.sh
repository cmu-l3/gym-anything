#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_diagnostic_logging results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

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

start_time = float(open('/tmp/task_start_time.txt').read().strip())

# Check for new exam configuration named 'Engineering Basics - DEBUG'
config_exists_str = db_query(
    "SELECT COUNT(*) FROM configuration_node WHERE name='Engineering Basics - DEBUG' AND type='EXAM_CONFIG'"
)
config_exists = int(config_exists_str) if config_exists_str.isdigit() else 0

# Get config details if it exists
config_id = ""
attributes_dict = {}

if config_exists > 0:
    config_id = db_query(
        "SELECT id FROM configuration_node WHERE name='Engineering Basics - DEBUG' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1"
    )
    
    # Try to extract the configuration attributes to verify detailed settings
    if config_id:
        attrs_raw = db_query(
            f"SELECT ad.name, ca.value FROM configuration_attribute ca JOIN attribute_definition ad ON ca.definition_id = ad.id WHERE ca.node_id={config_id}"
        )
        if attrs_raw:
            for line in attrs_raw.split('\n'):
                if '\t' in line:
                    key, val = line.split('\t', 1)
                    attributes_dict[key.strip()] = val.strip()

# Check if Firefox is running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'config_exists': config_exists > 0,
    'config_id': config_id,
    'attributes': attributes_dict,
    'firefox_running': firefox_running,
}

with open('/tmp/configure_diagnostic_logging_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="