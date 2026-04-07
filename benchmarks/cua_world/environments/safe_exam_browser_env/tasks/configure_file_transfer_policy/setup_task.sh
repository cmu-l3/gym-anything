#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_file_transfer_policy task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Prepare the specific exam configuration in the database
echo "Preparing 'CS101 Midterm' configuration..."
python3 << 'PYEOF'
import subprocess
import time

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True
    )
    return result.stdout.strip()

# Check if we have EXAM_CONFIG nodes
count = db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'")
if int(count or 0) == 0:
    print("Warning: No EXAM_CONFIG found. The seed script might not have run.")
    # Insert a dummy one if needed (fallback)
    db_query("INSERT INTO configuration_node (name, description, type, status) VALUES ('CS101 Midterm', 'Midterm Exam', 'EXAM_CONFIG', 'ACTIVE')")
else:
    # Rename the first one to 'CS101 Midterm'
    db_query("UPDATE configuration_node SET name='CS101 Midterm' WHERE type='EXAM_CONFIG' LIMIT 1")

# Get the ID
node_id = db_query("SELECT id FROM configuration_node WHERE name='CS101 Midterm' LIMIT 1")

if node_id:
    # Ensure attributes are explicitly false/disabled before task starts
    db_query(f"DELETE FROM configuration_attribute WHERE configuration_node_id={node_id} AND name IN ('allowDownloads', 'allowUploads')")
    db_query(f"INSERT INTO configuration_attribute (configuration_node_id, name, value) VALUES ({node_id}, 'allowDownloads', 'false')")
    db_query(f"INSERT INTO configuration_attribute (configuration_node_id, name, value) VALUES ({node_id}, 'allowUploads', 'false')")
    print(f"Successfully prepared config node ID: {node_id}")
else:
    print("Error: Could not find or create target node.")
PYEOF

# Record baseline
record_baseline "configure_file_transfer_policy"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server to put agent at a good starting point
login_seb_server "super-admin" "admin"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="