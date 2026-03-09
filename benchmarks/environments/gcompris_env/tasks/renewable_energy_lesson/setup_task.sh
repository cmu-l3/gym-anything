#!/bin/bash
set -e
echo "=== Setting up Renewable Energy Lesson Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/renewable_energy_screenshot.png
rm -f /home/ga/Documents/renewable_energy_lesson_note.txt
rm -f /tmp/task_result.json

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Ensure GCompris is running and at the main menu
kill_gcompris
launch_gcompris
maximize_gcompris

# 4. Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "GCompris is open at the main menu."
echo "Ready for agent to navigate to Science > Renewable Energy."