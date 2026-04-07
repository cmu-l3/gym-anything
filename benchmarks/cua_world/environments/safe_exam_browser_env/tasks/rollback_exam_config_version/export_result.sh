#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting rollback_exam_config_version results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to extract SEB Server database state
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
    if result.returncode != 0:
        return []
    output = result.stdout.strip()
    return output.split('\n') if output else []

start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except:
    pass

nodes = []
try:
    # Get all EXAM_CONFIG nodes
    node_rows = db_query("SELECT id, name, description FROM configuration_node WHERE type='EXAM_CONFIG'")
    for row in node_rows:
        parts = row.split('\t')
        if len(parts) >= 3:
            node_id = parts[0]
            name = parts[1]
            desc = parts[2]
            
            # Get version history for this node from the configuration table
            history_rows = db_query(f"SELECT id, description FROM configuration WHERE configuration_node_id={node_id}")
            versions = []
            for h_row in history_rows:
                h_parts = h_row.split('\t')
                if len(h_parts) >= 1:
                    v_id = h_parts[0]
                    v_desc = h_parts[1] if len(h_parts) > 1 else ""
                    versions.append({"id": v_id, "description": v_desc})
            
            nodes.append({
                "id": node_id,
                "name": name,
                "current_description": desc,
                "version_count": len(versions),
                "history": versions
            })
except Exception as e:
    print(f"Error querying database: {e}")

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'nodes': nodes,
    'firefox_running': firefox_running,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/rollback_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Database extraction complete. Sample nodes found:", len(nodes))
PYEOF

# Ensure permissions are open for the verifier
chmod 666 /tmp/rollback_task_result.json 2>/dev/null || sudo chmod 666 /tmp/rollback_task_result.json 2>/dev/null || true

echo "=== Export complete ==="