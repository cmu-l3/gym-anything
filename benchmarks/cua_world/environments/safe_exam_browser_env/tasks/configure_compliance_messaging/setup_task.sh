#!/bin/bash
echo "=== Setting up configure_compliance_messaging task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Use a Python script to interact safely with the database and ensure the environment is ready
python3 << 'PYEOF'
import subprocess
import time

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-B', '-e', query],
        capture_output=True, text=True
    )
    return result.stdout.strip()

# 1. Ensure at least one EXAM_CONFIG exists. If not, trigger the seeder.
count = db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'")
if not count or int(count) == 0:
    print("No exam configs found, running seeder...")
    subprocess.run(['python3', '/workspace/data/seed_exam_data.py'])
    time.sleep(5)

# 2. Guarantee an EXAM_CONFIG named "Law 101 Final" exists
exists = db_query("SELECT id FROM configuration_node WHERE name='Law 101 Final' AND type='EXAM_CONFIG' LIMIT 1")
if not exists:
    print("Renaming an existing configuration to 'Law 101 Final'")
    db_query("UPDATE configuration_node SET name='Law 101 Final' WHERE type='EXAM_CONFIG' LIMIT 1")

# 3. ANTI-GAMING: Clear out any pre-existing text that matches our target verification strings
# This ensures the verifier ONLY passes if the agent inputs the text during the task
db_query("""
DELETE cv FROM configuration_value cv
JOIN configuration_node cn ON cn.active_configuration_id = cv.configuration_id
WHERE cn.name = 'Law 101 Final' AND cv.value LIKE '%unauthorized help%';
""")
db_query("""
DELETE cv FROM configuration_value cv
JOIN configuration_node cn ON cn.active_configuration_id = cv.configuration_id
WHERE cn.name = 'Law 101 Final' AND cv.value LIKE '%action cannot be undone%';
""")
print("Cleared target compliance strings from database to enforce anti-gaming.")
PYEOF

# Record baseline for standard tracking
record_baseline "configure_compliance_messaging" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should edit the 'Law 101 Final' config to add specific Disclaimer and Quit messages."