#!/bin/bash
set -e
echo "=== Setting up audit_jicofo_logs task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for log filtering and anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Clean up any previous run artifacts
rm -f /home/ga/merger_audit_log.txt
rm -f /tmp/ground_truth_logs.txt

# Start Firefox fresh at the landing page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "TASK: 1. Join 'MergerDiscussion'. 2. Find creation log in jicofo container. 3. Save line to /home/ga/merger_audit_log.txt"