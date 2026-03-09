#!/bin/bash
set -e
echo "=== Setting up Tangram Puzzle Task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# record initial database state (if it exists) to detect changes later
DB_FILE="/home/ga/.local/share/gcompris-qt/gcompris-internal.db"
if [ -f "$DB_FILE" ]; then
    cp "$DB_FILE" /tmp/initial_gcompris.db
else
    echo "No initial database found."
fi

# Kill any existing instances
kill_gcompris

# Launch GCompris at the main menu
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Maximize window
maximize_gcompris
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent must navigate to Puzzle category -> Tangram and solve the puzzle."