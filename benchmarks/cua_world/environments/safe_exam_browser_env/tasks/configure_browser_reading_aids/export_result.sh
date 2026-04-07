#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_browser_reading_aids results ==="

# Capture final screenshot
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
        print(f"DB Query failed: {e}")
        return ""

start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

# Check if the specific config node exists
node_id = db_query("SELECT id FROM configuration_node WHERE name='Literature Analysis Exam' ORDER BY id DESC LIMIT 1")

config_values = {}
if node_id:
    # Get the active configuration associated with the node
    config_id = db_query(f"SELECT id FROM configuration WHERE node_id={node_id} ORDER BY id DESC LIMIT 1")
    if config_id:
        # Extract all configuration attributes mapped to their boolean/string values for this exam
        query = f"SELECT ca.name, cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.attribute_id = ca.id WHERE cv.configuration_id={config_id}"
        rows = db_query(query)
        if rows:
            for row in rows.split('\n'):
                if '\t' in row:
                    k, v = row.split('\t', 1)
                    config_values[k] = v

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    "task_start": start_time,
    "task_end": time.time(),
    "config_node_id": node_id,
    "config_values": config_values,
    "firefox_running": firefox_running,
    "screenshot_path": "/tmp/final_screenshot.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON Result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="