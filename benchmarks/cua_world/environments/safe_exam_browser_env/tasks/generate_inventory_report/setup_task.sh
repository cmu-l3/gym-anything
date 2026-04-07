#!/bin/bash
echo "=== Setting up generate_inventory_report task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server and MariaDB are accessible
wait_for_seb_server 120

# Clean up any pre-existing report to ensure a clean state
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/seb_inventory_report.json 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# Launch Firefox just to demonstrate SEB Server is up and provide environment context
launch_firefox "http://localhost:8080"
sleep 5

# Focus the terminal if it exists, otherwise just stay in browser
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot as evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should query the database and generate ~/Documents/seb_inventory_report.json"