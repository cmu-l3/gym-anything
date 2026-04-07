#!/bin/bash
echo "=== Setting up vision_inspection_setup task ==="

source /workspace/scripts/task_utils.sh

# Create exports directory and ensure proper ownership
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/inspection_rgb.png 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/inspection_depth.png 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/scene_objects.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/inspection_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp for file creation checks
date +%s > /tmp/vision_inspection_setup_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent must construct the scene, spawn objects, and setup vision sensor programmatically
launch_coppeliasim

# Focus and maximize the CoppeliaSim window
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs to provide a clean state
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/vision_inspection_setup_start.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must construct the inspection station via ZMQ Remote API."