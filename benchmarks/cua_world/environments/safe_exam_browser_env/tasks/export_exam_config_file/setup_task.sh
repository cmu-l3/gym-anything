#!/bin/bash
echo "=== Setting up export_exam_config_file task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Ensure Downloads directory exists and is empty of .seb files
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/*.seb

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Create or rename an exam config to 'Anatomy Midterm Config' so it exists for the task
echo "Ensuring 'Anatomy Midterm Config' exists in the database..."
EXISTS=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG';" 2>/dev/null || echo "0")

if [ "$EXISTS" -gt 0 ]; then
    # Rename an existing config
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "UPDATE configuration_node SET name='Anatomy Midterm Config', description='SEB lockdown configuration for Anatomy 201 Midterm - Fall 2024' WHERE type='EXAM_CONFIG' LIMIT 1;" 2>/dev/null || true
else
    # Insert a new basic config
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "INSERT INTO configuration_node (name, description, type) VALUES ('Anatomy Midterm Config', 'SEB lockdown configuration for Anatomy 201 Midterm - Fall 2024', 'EXAM_CONFIG');" 2>/dev/null || true
fi

# Record baseline state
record_baseline "export_exam_config_file"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot showing logged-in state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should navigate to Exam Configuration, select 'Anatomy Midterm Config', and export it."