#!/bin/bash
echo "=== Setting up configure_network_proxy task ==="

source /workspace/scripts/task_utils.sh

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_start.png /tmp/task_final.png 2>/dev/null || true

# Record task start time (anti-gaming baseline)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Wait for SEB Server to be ready
wait_for_seb_server 180

# Create the "Engineering Basics" Exam Configuration if it doesn't exist
# To ensure the DB state is valid, we try to rename an existing config template
EXISTS=$(seb_db_query "SELECT COUNT(*) FROM configuration_node WHERE name='Engineering Basics'")

if [ "$EXISTS" -eq "0" ]; then
    echo "Creating 'Engineering Basics' configuration..."
    # Try to find an existing EXAM_CONFIG to rename
    ANY_ID=$(seb_db_query "SELECT id FROM configuration_node WHERE type='EXAM_CONFIG' LIMIT 1")
    if [ -n "$ANY_ID" ]; then
        seb_db_query "UPDATE configuration_node SET name='Engineering Basics' WHERE id=$ANY_ID"
    else
        # Fallback minimal insert
        seb_db_query "INSERT INTO configuration_node (name, type, status) VALUES ('Engineering Basics', 'EXAM_CONFIG', 'CONSTRUCTION')"
    fi
fi

# Launch Firefox and Login
launch_firefox "http://localhost:8080"
login_seb_server "super-admin" "admin"
sleep 2

# Take initial screenshot showing starting state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="