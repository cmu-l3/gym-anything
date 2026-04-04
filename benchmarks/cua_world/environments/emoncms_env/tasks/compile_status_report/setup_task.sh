#!/bin/bash
echo "=== Setting up compile_status_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Remove any existing report file to ensure a fresh start
rm -f /home/ga/emoncms_status_report.json

# Ensure Emoncms is up and reachable
wait_for_emoncms

# Launch Firefox to the Feeds page so the agent can see the data immediately
# The agent is logged in as admin via the launch_firefox_to helper
launch_firefox_to "http://localhost/feed/view" 10

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="