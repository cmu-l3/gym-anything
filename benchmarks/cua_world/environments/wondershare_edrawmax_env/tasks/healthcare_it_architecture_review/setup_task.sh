#!/bin/bash
echo "=== Setting up healthcare_it_architecture_review task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/Documents/clearmed_architecture.eddx 2>/dev/null || true
rm -f /home/ga/Documents/clearmed_architecture.png 2>/dev/null || true
mkdir -p /home/ga/Documents

# Record task start timestamp AFTER cleanup
date +%s > /tmp/healthcare_it_architecture_review_start_ts

# Launch EdrawMax fresh (opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
sleep 2
take_screenshot /tmp/healthcare_it_architecture_review_start.png
echo "Start state screenshot saved to /tmp/healthcare_it_architecture_review_start.png"

echo "=== healthcare_it_architecture_review task setup complete ==="
echo "EdrawMax is open. Agent should create a 2-page architecture document and save as /home/ga/Documents/clearmed_architecture.eddx"
