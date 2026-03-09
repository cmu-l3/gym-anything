#!/bin/bash
set -e
cd /workspace/tasks/create_scheduler_task || cd "$(dirname "$0")"

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_scheduler_task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Delete the task if it already exists
# Using docker exec to run mysql command inside the db container
echo "Cleaning up any existing task..."
docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e \
  "DELETE FROM scheduler_task_config WHERE name = 'Hourly Alert Sync';" 2>/dev/null || true

# Record initial count of tasks
INITIAL_COUNT=$(docker exec bahmni-openmrsdb mysql -N -s -u openmrs-user -ppassword openmrs -e \
  "SELECT count(*) FROM scheduler_task_config;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Ensure Bahmni/OpenMRS is reachable before starting browser
wait_for_bahmni 120

# Start browser at Bahmni Home (login page)
# The task description says "browser is currently open to the Bahmni home page"
restart_browser "${BAHMNI_LOGIN_URL}" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="