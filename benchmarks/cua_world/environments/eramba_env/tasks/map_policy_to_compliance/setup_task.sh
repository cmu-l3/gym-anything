#!/bin/bash
set -e
echo "=== Setting up map_policy_to_compliance task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming (using DB server time if possible, else system time)
# We use docker exec to get DB time to ensure synchronization with 'created' timestamps
DB_TIME=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT UNIX_TIMESTAMP(NOW());" 2>/dev/null || date +%s)
echo "$DB_TIME" > /tmp/task_start_time.txt
echo "Task start time (DB): $DB_TIME"

# 2. Ensure Firefox is running and logged in (or at login screen)
# We navigate to the Dashboard to ensure a neutral starting state
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"
sleep 5

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="