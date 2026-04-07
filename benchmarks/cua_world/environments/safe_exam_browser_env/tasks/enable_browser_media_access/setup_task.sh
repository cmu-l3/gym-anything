#!/bin/bash
echo "=== Setting up enable_browser_media_access task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time (anti-gaming check)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

echo "Seeding database with the target exam configuration..."
# Inject the starting exam configuration directly into the DB so the agent just has to edit it
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
SET @inst = (SELECT id FROM institution LIMIT 1);
INSERT INTO configuration_node (name, description, type, status, institution_id) 
SELECT 'Oral Communication 2025', 'Requires camera and mic access', 'EXAM_CONFIG', 'CREATED', @inst
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM configuration_node WHERE name='Oral Communication 2025' AND type='EXAM_CONFIG');

SET @node_id = (SELECT id FROM configuration_node WHERE name='Oral Communication 2025' LIMIT 1);
INSERT INTO configuration (configuration_node_id, name)
SELECT @node_id, 'Oral Communication 2025'
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM configuration WHERE configuration_node_id=@node_id);
" || echo "WARNING: DB seeding failed, agent will need to create it manually."

# Record baseline for anti-gaming
record_baseline "enable_browser_media_access" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server automatically
login_seb_server "super-admin" "admin"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Target: Update 'Oral Communication 2025' to enable Camera and Microphone."