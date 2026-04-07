#!/bin/bash
echo "=== Setting up multi_role_department_provisioning task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json \
    /tmp/multi_role_department_provisioning_result.json \
    /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline database state
record_baseline "multi_role_department_provisioning"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent must provision 4 department user accounts + 1 connection config:"
echo "  1. cs.admin (Elena Vasquez) - Exam Administrator"
echo "  2. math.admin (Robert Chen) - Exam Administrator"
echo "  3. physics.supporter (Aisha Okonkwo) - Exam Supporter"
echo "  4. it.supervisor (Marcus Webb) - Institutional Administrator"
echo "  5. Connection config 'Department Hub Connection Config'"
