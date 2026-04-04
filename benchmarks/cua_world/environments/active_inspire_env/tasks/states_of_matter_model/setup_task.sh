#!/bin/bash
# Setup script for States of Matter Particle Model task

echo "=== Setting up States of Matter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Clean up any previous attempts
TARGET_FILE="/home/ga/Documents/Flipcharts/particle_model.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/particle_model.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 2

# Focus the window
focus_activinspire

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="