#!/bin/bash
echo "=== Setting up Generate Patient Demographics Report Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Remove output file if it exists (ensure fresh start)
rm -f /home/ga/patient_report_count.txt

# Ensure LibreHealth EHR is accessible
wait_for_librehealth 120

# Launch Firefox at the login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="