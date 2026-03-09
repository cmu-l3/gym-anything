#!/bin/bash
echo "=== Setting up import_configure_exam task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline
record_baseline "import_configure_exam"

# Verify the Testing LMS is configured in the demo
python3 << 'PYEOF'
import subprocess

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

# Check for LMS setup (Testing/Mock LMS)
lms_count = db_query("SELECT COUNT(*) FROM lms_setup")
print(f"LMS setups found: {lms_count}")

# List LMS configurations
lms_list = db_query("SELECT id, name, lms_type FROM lms_setup")
print(f"LMS configurations: {lms_list}")
PYEOF

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should import an exam from the Testing LMS and configure it with monitoring indicators"
