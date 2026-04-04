#!/bin/bash
echo "=== Setting up draw_basic_shapes task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any existing file with the expected name (clean start)
rm -f /home/ga/Documents/Flipcharts/shapes_lesson.flipchart 2>/dev/null || true
rm -f /home/ga/Documents/Flipcharts/shapes_lesson.flp 2>/dev/null || true

# Record initial timestamp
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus ActivInspire window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
