#!/bin/bash
echo "=== Setting up cross_domain_developmental_battery task ==="

source /workspace/scripts/task_utils.sh

# Remove any stale report file BEFORE recording timestamp
rm -f /home/ga/Desktop/developmental_assessment_battery.txt

# Record task start timestamp AFTER cleanup
date +%s > /tmp/task_start_ts_dev_battery

# Kill any running GCompris
kill_gcompris

# Launch GCompris at main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

take_screenshot /tmp/dev_battery_start.png

echo "=== Setup complete. GCompris is at main menu. ==="
echo "Agent must:"
echo "  1. Navigate Math category and complete a math activity"
echo "  2. Navigate Language category and complete a language activity"
echo "  3. Navigate Science category and complete a science activity"
echo "  4. Navigate Games category and complete a game activity"
echo "  5. Write a 4-domain developmental assessment battery to"
echo "     ~/Desktop/developmental_assessment_battery.txt"
