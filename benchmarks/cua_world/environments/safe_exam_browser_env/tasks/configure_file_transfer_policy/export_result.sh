#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_file_transfer_policy results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout.strip()

start_time = float(open('/tmp/task_start_time.txt').read().strip())
end_time = time.time()

# Check values for 'CS101 Midterm'
node_id = db_query("SELECT id FROM configuration_node WHERE name='CS101 Midterm' LIMIT 1")

downloads_enabled = False
uploads_enabled = False
downloads_val = ""
uploads_val = ""

if node_id:
    dl_val = db_query(f"SELECT value FROM configuration_attribute WHERE configuration_node_id={node_id} AND name='allowDownloads'")
    ul_val = db_query(f"SELECT value FROM configuration_attribute WHERE configuration_node_id={node_id} AND name='allowUploads'")
    
    downloads_val = dl_val.lower() if dl_val else "false"
    uploads_val = ul_val.lower() if ul_val else "false"
    
    # Check for truthy strings in SEB DB ('true', '1')
    downloads_enabled = downloads_val in ['true', '1']
    uploads_enabled = uploads_val in ['true', '1']

# Check if application is running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'task_start_time': start_time,
    'task_end_time': end_time,
    'node_found': bool(node_id),
    'node_id': node_id,
    'downloads_enabled': downloads_enabled,
    'uploads_enabled': uploads_enabled,
    'raw_downloads_val': downloads_val,
    'raw_uploads_val': uploads_val,
    'firefox_running': firefox_running
}

with open('/tmp/configure_file_transfer_policy_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="