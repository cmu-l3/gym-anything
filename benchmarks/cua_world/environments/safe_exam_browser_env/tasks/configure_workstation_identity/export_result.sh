#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_workstation_identity results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    try:
        res = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, check=True
        )
        return res.stdout.strip()
    except subprocess.CalledProcessError as e:
        return ""

start_time = 0.0
if os.path.exists('/tmp/task_start_time.txt'):
    start_time = float(open('/tmp/task_start_time.txt').read().strip())

node_id = db_query("SELECT id FROM configuration_node WHERE name='Engineering Final Exam 2026' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

attributes = {}
config_id = None
if node_id:
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")
    if config_id:
        cols = db_query("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='configuration_attribute' AND TABLE_SCHEMA='SEBServer'")
        col_list = [c.strip().lower() for c in cols.split('\n') if c.strip()]
        
        key_col = next((c for c in ['key', 'name', 'attribute_key', 'property'] if c in col_list), 'key')
        val_col = next((c for c in ['value', 'attribute_value'] if c in col_list), 'value')
        
        raw_attrs = db_query(f"SELECT \`{key_col}\`, \`{val_col}\` FROM configuration_attribute WHERE configuration_id={config_id}")
        
        for line in raw_attrs.split('\n'):
            if '\t' in line:
                k, v = line.split('\t', 1)
                attributes[k] = v

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'task_start_time': start_time,
    'timestamp': time.time(),
    'node_id': node_id,
    'config_id': config_id,
    'attributes': attributes,
    'firefox_running': firefox_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="