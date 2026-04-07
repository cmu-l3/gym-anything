#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_exam_input_security results ==="

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
        out = result.stdout.strip()
        if "ERROR" in out or "Unknown column" in out:
            return ""
        return out
    except Exception:
        return ""

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = time.time()

# Find the exam configuration named 'Creative Writing Midterm'
node_id = db_query("SELECT id FROM configuration_node WHERE name='Creative Writing Midterm' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

attributes = {}
config_exists = False

if node_id:
    config_exists = True
    # Find the linked configuration ID to get the attributes
    config_id = db_query(f"SELECT current_configuration_id FROM configuration_node WHERE id={node_id}")
    if not config_id:
        config_id = db_query(f"SELECT configuration_id FROM configuration_node WHERE id={node_id}")
    
    if config_id:
        # Try multiple queries to find attributes depending on SEB Server schema version
        for col_name in ['name', 'key_name', 'key', 'property_name']:
            query = f"SELECT ca.{col_name}, cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_id={config_id}"
            rows = db_query(query)
            if rows and len(rows.split('\n')) > 0:
                for row in rows.split('\n'):
                    if '\t' in row:
                        k, v = row.split('\t', 1)
                        attributes[k.strip()] = v.strip()
                if attributes:
                    break

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'config_exists': config_exists,
    'node_id': node_id,
    'attributes': attributes,
    'firefox_running': firefox_running,
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export JSON result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="