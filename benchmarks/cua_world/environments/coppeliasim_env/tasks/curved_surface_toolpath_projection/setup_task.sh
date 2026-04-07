#!/bin/bash
echo "=== Setting up curved_surface_toolpath_projection task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/toolpath.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/toolpath_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/task_start_ts

# STEP 3: Launch CoppeliaSim with an EMPTY scene
# The agent must construct the scene objects programmatically
echo "Launching empty CoppeliaSim scene..."
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to build the target, compute the toolpath, and visualize it."