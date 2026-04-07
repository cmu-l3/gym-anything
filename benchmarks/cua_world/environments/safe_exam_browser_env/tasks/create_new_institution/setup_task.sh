#!/bin/bash
echo "=== Setting up create_new_institution task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/initial_state.json /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Helper function to execute DB queries
db_query() {
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "$1" 2>/dev/null
}

# ANTI-GAMING: Ensure target institution doesn't already exist (from previous failed attempts)
echo "Cleaning up any pre-existing target institutions..."
db_query "DELETE FROM institution WHERE name LIKE '%Pacific Northwest%';"

# Record baseline state
INITIAL_COUNT=$(db_query "SELECT COUNT(*) FROM institution;" || echo "0")
echo "Initial institution count: $INITIAL_COUNT"

# Save baseline to JSON
cat > /tmp/initial_state.json << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "task_start_time": $(cat /tmp/task_start_time.txt)
}
EOF

# Launch Firefox and navigate to SEB Server login
launch_firefox "http://localhost:8080"
sleep 5

# Ensure window is focused and maximized
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot to prove starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="