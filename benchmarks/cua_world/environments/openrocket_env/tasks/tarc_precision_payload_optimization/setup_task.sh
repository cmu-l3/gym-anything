#!/bin/bash
echo "=== Setting up tarc_precision_payload_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
TARGET_ORK="/home/ga/Documents/rockets/tarc_competition_design.ork"

# Ensure starting from a clean slate
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "/home/ga/Documents/exports/tarc_engineering_notebook.md" 2>/dev/null || true
rm -f "/home/ga/Documents/exports/tarc_engineering_notebook.txt" 2>/dev/null || true

# Check if source exists, if not try alternative locations
if [ ! -f "$SOURCE_ORK" ]; then
    if [ -f "/workspace/data/rockets/simple_model_rocket.ork" ]; then
        cp "/workspace/data/rockets/simple_model_rocket.ork" "$SOURCE_ORK"
        chown ga:ga "$SOURCE_ORK"
    fi
fi

# Record ground truth and timestamp
date +%s > /tmp/task_start_time

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== tarc_precision_payload_optimization task setup complete ==="