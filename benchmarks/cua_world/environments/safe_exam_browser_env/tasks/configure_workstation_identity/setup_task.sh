#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_workstation_identity task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# We need to guarantee the "Engineering Final Exam 2026" configuration exists.
# We will use Python to query the DB, find an existing config, and rename it to our target.
echo "Preparing database state..."
python3 << 'PYEOF'
import subprocess
import json

def db_query(query):
    try:
        res = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, check=True
        )
        return res.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"DB Query failed: {e.stderr}")
        return ""

# Check if target already exists
target_node_id = db_query("SELECT id FROM configuration_node WHERE name='Engineering Final Exam 2026' AND type='EXAM_CONFIG' LIMIT 1")

if not target_node_id:
    # Find any existing EXAM_CONFIG to rename
    existing_node_id = db_query("SELECT id FROM configuration_node WHERE type='EXAM_CONFIG' LIMIT 1")
    
    if existing_node_id:
        db_query(f"UPDATE configuration_node SET name='Engineering Final Exam 2026' WHERE id={existing_node_id}")
        target_node_id = existing_node_id
        print(f"Renamed node {existing_node_id} to target.")
    else:
        # Fallback: insert a fresh one
        db_query("INSERT INTO configuration_node (name, type, status) VALUES ('Engineering Final Exam 2026', 'EXAM_CONFIG', 'ACTIVE')")
        target_node_id = db_query("SELECT id FROM configuration_node WHERE name='Engineering Final Exam 2026' AND type='EXAM_CONFIG' LIMIT 1")
        if target_node_id:
            db_query(f"INSERT INTO configuration (configuration_node_id, status) VALUES ({target_node_id}, 'ACTIVE')")
            print("Created new target node.")

# Clear any pre-existing relevant attributes to prevent false positives
if target_node_id:
    config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={target_node_id} ORDER BY id DESC LIMIT 1")
    if config_id:
        # Determine column names dynamically to be safe against schema changes
        cols = db_query("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='configuration_attribute' AND TABLE_SCHEMA='SEBServer'")
        col_list = [c.strip().lower() for c in cols.split('\n') if c.strip()]
        
        key_col = next((c for c in ['key', 'name', 'attribute_key', 'property'] if c in col_list), 'key')
        
        keys_to_clear = ['browserViewMode', 'mainBrowserWindowWidth', 'mainBrowserWindowHeight', 'userAgentAppend', 'userAgentSuffix']
        for k in keys_to_clear:
            db_query(f"DELETE FROM configuration_attribute WHERE configuration_id={config_id} AND \`{key_col}\`='{k}'")
        print(f"Cleared target attributes for config_id {config_id}.")
PYEOF

# Launch Firefox and navigate to SEB Server
echo "Launching browser..."
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="