#!/bin/bash
set -euo pipefail

echo "=== Setting up customize_quit_warning_message task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

echo "Seeding baseline Exam Configuration..."
# Seed the database with the target configuration so the agent has a starting point
# We use ON DUPLICATE KEY UPDATE to ensure it's idempotent
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
INSERT INTO configuration_node (name, description, type, status) 
VALUES ('Chemistry 201 - Midterm', 'Midterm examination configuration', 'EXAM_CONFIG', 'UNDER_CONSTRUCTION')
ON DUPLICATE KEY UPDATE description='Midterm examination configuration';
" 2>/dev/null || echo "WARNING: Direct DB insert failed, agent will need to create it."

# Launch Firefox and navigate to SEB Server login
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Automate login to save agent time
login_seb_server "super-admin" "admin"
sleep 3

# Take initial state screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="