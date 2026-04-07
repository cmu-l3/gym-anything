#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting enable_browser_media_access results ==="

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

# Read task start time
start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except:
    pass

# 1. Check if the configuration node exists
node_id = db_query("SELECT id FROM configuration_node WHERE name='Oral Communication 2025' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

media_settings = []
config_id = ""

if node_id:
    # 2. Get the linked configuration ID
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")
    
    if config_id:
        # 3. Dump all media/video/audio/camera related attributes
        # We use a broad LIKE query to be robust against SEB version schema changes
        query = f"""
        SELECT name, value 
        FROM configuration_attribute 
        WHERE configuration_id={config_id} 
        AND (LOWER(name) LIKE '%video%' 
             OR LOWER(name) LIKE '%audio%' 
             OR LOWER(name) LIKE '%camera%' 
             OR LOWER(name) LIKE '%mic%')
        """
        attrs = db_query(query)
        
        if attrs:
            for line in attrs.split('\n'):
                if '\t' in line:
                    key, val = line.split('\t', 1)
                    media_settings.append({
                        "key": key.strip(),
                        "value": val.strip()
                    })

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'config_exists': bool(node_id),
    'node_id': node_id,
    'config_id': config_id,
    'media_settings': media_settings,
    'firefox_running': firefox_running,
}

# Safely write the output
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
os.chmod('/tmp/task_result.json', 0o666)

print("Exported JSON Result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="