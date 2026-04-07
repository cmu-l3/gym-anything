#!/bin/bash
echo "=== Exporting configure_network_proxy results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query database for the configuration using Python for safe JSON handling
python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    """Run a MySQL query against the Docker DB and return the raw string."""
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True
    )
    return result.stdout.strip()

# Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = float(f.read().strip())
except Exception:
    task_start = 0

node_id = db_query("SELECT id FROM configuration_node WHERE name='Engineering Basics' LIMIT 1")
config_data = {}
changed_ts = 0

if node_id:
    # Get the latest active configuration for this node
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY changed DESC LIMIT 1")
    
    if config_id:
        # Get timestamp in UNIX format to easily compare against bash `date +%s`
        changed_val = db_query(f"SELECT UNIX_TIMESTAMP(changed) FROM configuration WHERE id={config_id}")
        try:
            changed_ts = float(changed_val)
        except Exception:
            changed_ts = 0
            
        # Get settings key-values
        raw_settings = db_query(f"SELECT ca.name, cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_id={config_id}")
        
        if raw_settings:
            for line in raw_settings.split('\n'):
                if '\t' in line:
                    k, v = line.split('\t', 1)
                    config_data[k.strip()] = v.strip()

# Check if Firefox was still running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    "node_id": node_id,
    "changed_ts": changed_ts,
    "task_start_ts": task_start,
    "settings": config_data,
    "export_time": time.time(),
    "firefox_running": firefox_running
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure file has proper permissions for the verifier to read
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="