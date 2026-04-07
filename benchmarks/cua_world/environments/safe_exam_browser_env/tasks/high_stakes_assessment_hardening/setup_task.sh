#!/bin/bash
echo "=== Setting up high_stakes_assessment_hardening task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json \
    /tmp/high_stakes_assessment_hardening_result.json \
    /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline database state
record_baseline "high_stakes_assessment_hardening"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent must harden the CPA exam environment:"
echo "  1. Create exam configuration 'CPA Board Exam - Maximum Security'"
echo "  2. Create connection config 'CPA Exam Connection' with password"
echo "  3. Create exam template 'CPA Board Exam Template'"
echo "  4. Add 'Last Ping Time' indicator 'Connection Monitor' (warn:5000, danger:12000)"
echo "  5. Add 'Error-Log Counter' indicator 'Security Alert Monitor' (warn:3, danger:10)"
