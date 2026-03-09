#!/bin/bash
echo "=== Setting up science_experiment_catalog task ==="

source /workspace/scripts/task_utils.sh

# Remove any stale report file BEFORE recording timestamp
rm -f /home/ga/Desktop/science_curriculum_report.txt

# Record task start timestamp AFTER cleanup
date +%s > /tmp/task_start_ts_science_catalog

# Kill any running GCompris
kill_gcompris

# Launch GCompris at main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

take_screenshot /tmp/science_catalog_start.png

echo "=== Setup complete. GCompris is at main menu. ==="
echo "Agent must:"
echo "  1. Navigate to Science/Experiment category"
echo "  2. Open and interact with at least 3 experiment activities"
echo "     (including physics experiments like Gravity/Watercycle AND"
echo "      color experiments like Mixing paint/light colors)"
echo "  3. Write NGSS Curriculum Alignment Report to"
echo "     ~/Desktop/science_curriculum_report.txt"
