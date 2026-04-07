#!/bin/bash
echo "=== Setting up trajectory_clearance_audit task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/clearance_audit.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/audit_summary.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/audit_scene.ttt 2>/dev/null || true

# STEP 2: Record task start timestamp (crucial for anti-gaming)
date +%s > /tmp/clearance_audit_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# The agent must programmatically build the scene (load robot, spawn obstacles)
echo "Launching empty CoppeliaSim scene..."
launch_coppeliasim

# Focus and maximize window for clear agent visibility
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup or update dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot to prove empty starting state
sleep 2
take_screenshot /tmp/clearance_audit_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must load a robot, create obstacles, run clearance audit, and export results."