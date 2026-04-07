#!/bin/bash
echo "=== Setting up configure_seb_browser_security task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Attempt to pre-create the exam configuration in the database
# This ensures the starting state described in the task exists.
echo "Seeding initial exam configuration..."
python3 << 'PYEOF'
import subprocess

def db_query(query):
    subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=10
    )

try:
    # Insert node
    db_query("INSERT INTO configuration_node (name, type, description, status) VALUES ('LPN Certification Practice Exam', 'EXAM_CONFIG', 'Practice exam for LPN certification', 'CONSTRUCTION');")
    # Get ID and insert configuration mapping
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', "SELECT id FROM configuration_node WHERE name='LPN Certification Practice Exam' ORDER BY id DESC LIMIT 1"],
        capture_output=True, text=True
    )
    node_id = result.stdout.strip()
    if node_id:
        db_query(f"INSERT INTO configuration (configuration_node_id) VALUES ({node_id});")
        print(f"Successfully seeded configuration with ID {node_id}")
except Exception as e:
    print(f"Warning: Database seed encountered an issue: {e}")
PYEOF

# Record baseline
record_baseline "configure_seb_browser_security" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 4

# Navigate explicitly to the Exam Configuration page to save agent time
navigate_firefox "${SEB_SERVER_URL}/gui/configuration/exam"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should edit the SEB Settings for 'LPN Certification Practice Exam'"