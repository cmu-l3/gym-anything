#!/bin/bash
echo "=== Setting up CanSat Payload Expansion Retrofit Task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils.sh"; exit 1; }

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/rockets
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# Copy a fresh instance of the simple model rocket
cp /workspace/data/rockets/simple_model_rocket.ork /home/ga/Documents/rockets/simple_model_rocket.ork 2>/dev/null || \
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/A%20simple%20model%20rocket.ork" -O /home/ga/Documents/rockets/simple_model_rocket.ork

chown ga:ga /home/ga/Documents/rockets/simple_model_rocket.ork

# Remove any previous artifacts
rm -f /home/ga/Documents/rockets/cansat_retrofit.ork
rm -f /home/ga/Documents/exports/cansat_report.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the starting file
launch_openrocket "/home/ga/Documents/rockets/simple_model_rocket.ork"

# Wait for OpenRocket window to appear and prepare it
wait_for_openrocket 60
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take an initial screenshot to prove starting state
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="