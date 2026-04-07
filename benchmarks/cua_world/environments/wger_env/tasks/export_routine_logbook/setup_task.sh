#!/bin/bash
# Setup script for export_routine_logbook task

echo "=== Setting up export_routine_logbook task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the Downloads directory exists and is empty to prevent false positives
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/*.pdf
chown -R ga:ga /home/ga/Downloads

# Ensure wger is responding
wait_for_wger_page

# Launch Firefox to the wger dashboard (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/routine/overview/" 5

# Take a starting screenshot
take_screenshot /tmp/task_setup_initial.png

echo "=== Task setup complete: export_routine_logbook ==="
echo "Agent must download the PDF logbook for 'Push-Pull-Legs' and save it to /home/ga/Downloads/Push-Pull-Legs-Logbook.pdf"