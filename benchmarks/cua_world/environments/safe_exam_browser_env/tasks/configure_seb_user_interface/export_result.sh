#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_seb_user_interface results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to extract all current configuration values cleanly
python3 << 'PYEOF'
import subprocess
import json
import time
import os

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=15
        )
        return result.stdout.strip()
    except Exception:
        return ""

# Load Baseline
baseline = {}
if os.path.exists('/tmp/baseline_config_values.json'):
    try:
        with open('/tmp/baseline_config_values.json') as f:
            baseline = json.load(f)
    except:
        pass

# Check if Firefox is running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    "task_start_time": int(os.environ.get('TASK_START', 0)),
    "task_end_time": int(os.environ.get('TASK_END', int(time.time()))),
    "firefox_running": firefox_running,
    "config_exists": False,
    "config_values": {},
    "baseline": baseline
}

try:
    # Find the config node
    node_id = db_query("SELECT id FROM configuration_node WHERE name='Certification Exam Fall 2024' LIMIT 1")
    if node_id:
        result["config_exists"] = True
        result["node_id"] = node_id
        
        # Find the active configuration
        config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")
        
        if config_id:
            result["config_id"] = config_id
            
            # Extract all configuration attributes for this config
            raw_data = db_query(f"""
                SELECT ca.name, cv.value 
                FROM configuration_value cv 
                JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id 
                WHERE cv.configuration_id={config_id}
            """)
            
            for line in raw_data.split('\n'):
                if '\t' in line:
                    k, v = line.split('\t', 1)
                    result["config_values"][k] = v
except Exception as e:
    result["error"] = str(e)

# Save result safely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
    
print(f"Exported {len(result['config_values'])} configuration values.")
PYEOF

echo "=== Export complete ==="