#!/bin/bash
set -euo pipefail

echo "=== Setting up Monte Carlo OLS Simulation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure clean state
kill_gretl

# Create output directory
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Remove any existing target files to prevent false positives
rm -f /home/ga/Documents/gretl_output/monte_carlo.inp
rm -f /home/ga/Documents/gretl_output/monte_carlo_results.txt

# Launch Gretl GUI (empty, as this is a scripting task starting from scratch)
echo "Launching Gretl..."
launch_gretl "" "/home/ga/gretl_startup.log"

# Wait for window
wait_for_gretl 60 || true
sleep 5

# Handle startup dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus
maximize_gretl
focus_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="