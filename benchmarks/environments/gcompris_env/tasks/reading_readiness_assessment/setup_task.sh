#!/bin/bash
echo "=== Setting up reading_readiness_assessment task ==="

source /workspace/scripts/task_utils.sh

# Remove any stale report file BEFORE recording timestamp
rm -f /home/ga/Desktop/reading_readiness_report.txt

# Record task start timestamp AFTER cleanup
date +%s > /tmp/task_start_ts_reading_readiness

# Kill any running GCompris
kill_gcompris

# Launch GCompris at main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

take_screenshot /tmp/reading_readiness_start.png

echo "=== Setup complete. GCompris is at main menu. ==="
echo "Agent must navigate to Language/Reading category, explore Letters/Words/Vocabulary tabs,"
echo "interact with at least 4 activities, and write a reading readiness report to"
echo "~/Desktop/reading_readiness_report.txt"
