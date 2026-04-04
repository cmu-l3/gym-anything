#!/bin/bash
echo "=== Setting up Graph Traversal Analysis task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

# Ensure demodb exists and is populated (relies on env setup, but double check)
if ! orientdb_db_exists "demodb"; then
    echo "demodb missing, running setup..."
    /workspace/scripts/setup_orientdb.sh
fi

# Reset/Ensure clean state for report file
rm -f /home/ga/graph_analysis_report.txt

# Launch Firefox to OrientDB Studio Login
echo "Launching Firefox..."
kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Generate graph analysis report at /home/ga/graph_analysis_report.txt"