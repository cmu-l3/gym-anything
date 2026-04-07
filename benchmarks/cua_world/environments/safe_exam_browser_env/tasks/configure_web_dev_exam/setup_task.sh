#!/bin/bash
echo "=== Setting up configure_web_dev_exam task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Rename an existing exam configuration to 'CS302 Web Technologies' if one exists
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "UPDATE configuration_node SET name='CS302 Web Technologies' WHERE type='EXAM_CONFIG' LIMIT 1" 2>/dev/null || true

# Check if the target config was successfully updated/created
EXISTS=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM configuration_node WHERE name='CS302 Web Technologies'" 2>/dev/null)
if [ -z "$EXISTS" ] || [ "$EXISTS" = "0" ]; then
    # Insert one if it doesn't exist
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "INSERT INTO configuration_node (name, description, type, status, active) VALUES ('CS302 Web Technologies', 'Web Dev Final', 'EXAM_CONFIG', 'CREATED', 1)" 2>/dev/null || true
    CONFIG_ID=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT id FROM configuration_node WHERE name='CS302 Web Technologies' LIMIT 1" 2>/dev/null)
    if [ -n "$CONFIG_ID" ]; then
        docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "INSERT INTO configuration (configuration_node_id, version, active) VALUES ($CONFIG_ID, 1, 1)" 2>/dev/null || true
    fi
fi

# Clean slate: Ensure developer console and right mouse are false/not present in the baseline state
CONFIG_ID=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT id FROM configuration WHERE configuration_node_id=(SELECT id FROM configuration_node WHERE name='CS302 Web Technologies' LIMIT 1) ORDER BY version DESC LIMIT 1" 2>/dev/null)
if [ -n "$CONFIG_ID" ]; then
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "DELETE cv FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_id=$CONFIG_ID AND ca.name IN ('allowDeveloperConsole', 'enableRightMouse')" 2>/dev/null || true
fi

# Record baseline for anti-gaming checks
record_baseline "configure_web_dev_exam" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="