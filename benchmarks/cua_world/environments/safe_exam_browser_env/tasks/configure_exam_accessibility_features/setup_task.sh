#!/bin/bash
echo "=== Setting up configure_exam_accessibility_features task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time (used to verify changes were made during this session)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Attempt to seed the exam configuration directly into the database
# If this fails (due to schema variance), the task description instructs the agent to create it
echo "Seeding base exam configuration..."
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
INSERT INTO configuration_node (name, description, type, creation_date, changed_date, status, institution_id)
SELECT 'ENGL 204: Modernist Literature Final', 'Final Exam for Modernist Lit. Accessibility restricted.', 'EXAM_CONFIG', NOW(), NOW(), 'CONSTRUCTION', id FROM institution LIMIT 1;
" 2>/dev/null || echo "Note: Could not pre-seed config via SQL. Agent will create it if missing."

# Launch Firefox and navigate to SEB Server Dashboard
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot as proof of task start
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="