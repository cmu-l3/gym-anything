#!/bin/bash
echo "=== Setting up deactivate_seb_client_machine task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Inject the target client into the database
# We try multiple common configuration tables to ensure it appears in the UI
echo "Injecting target client 'Loaner-Laptop-22' into database..."
python3 << 'PYEOF'
import subprocess
import time

def db_query(query):
    try:
        subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=10
        )
    except Exception as e:
        print(f"DB query failed: {e}")

# Inject into seb_client_configuration table
db_query("INSERT IGNORE INTO seb_client_configuration (name, active) VALUES ('Loaner-Laptop-22', 1)")

# Inject into configuration_node table (used for generic configs in newer SEB Server versions)
db_query("INSERT IGNORE INTO configuration_node (name, type, active, description) VALUES ('Loaner-Laptop-22', 'CLIENT_CONFIG', 1, 'Loaner laptop configuration')")

print("Client injection completed.")
PYEOF

# Record baseline counts
record_baseline "deactivate_seb_client_machine" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server to set the starting state
login_seb_server "super-admin" "admin"
sleep 4

# Take initial screenshot showing the dashboard
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="