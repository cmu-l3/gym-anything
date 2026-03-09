#!/bin/bash
set -e
echo "=== Setting up Reassemble Sentences task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/sentence_report.txt
rm -f /home/ga/Documents/sentence_evidence.png
rm -f /tmp/task_result.json

# Ensure GCompris is running and clean
kill_gcompris
launch_gcompris

# Wait for window and maximize
sleep 5
maximize_gcompris

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is open at the main menu."
echo "Task: Navigate to Reading > Ordering Sentences, solve 5 puzzles, and report them."