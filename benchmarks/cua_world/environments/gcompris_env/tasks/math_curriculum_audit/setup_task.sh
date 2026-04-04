#!/bin/bash
echo "=== Setting up math_curriculum_audit task ==="

source /workspace/scripts/task_utils.sh

# Remove any stale report file BEFORE recording timestamp
rm -f /home/ga/Desktop/math_curriculum_audit.txt

# Record task start timestamp AFTER cleanup
date +%s > /tmp/task_start_ts_math_audit

# Kill any running GCompris
kill_gcompris

# Launch GCompris at main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

take_screenshot /tmp/math_audit_start.png

echo "=== Setup complete. GCompris is at main menu. ==="
echo "Agent must navigate to Math/Numbers category, explore Numeration/Arithmetic/Measures tabs,"
echo "interact with activities, and write a curriculum audit report to ~/Desktop/math_curriculum_audit.txt"
