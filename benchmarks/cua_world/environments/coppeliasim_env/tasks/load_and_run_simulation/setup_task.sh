#!/bin/bash
echo "=== Setting up load_and_run_simulation task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Clean any pre-existing output
rm -f /home/ga/Documents/CoppeliaSim/exports/simulation_running.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Kill any running CoppeliaSim instances for clean state
kill_coppeliasim

# Launch CoppeliaSim with empty scene (agent must load scene via ZMQ API)
launch_coppeliasim

# Focus and maximize
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "CoppeliaSim is running with empty scene."
echo "Agent must use ZMQ Remote API to load scene, start simulation, and take screenshot."
