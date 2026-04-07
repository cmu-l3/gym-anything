#!/bin/bash
echo "=== Setting up full_semester_exam_rollout task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json \
    /tmp/full_semester_exam_rollout_result.json \
    /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline database state
record_baseline "full_semester_exam_rollout"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent must provision the full semester exam environment:"
echo "  1. Create connection config 'Finals Week Secure Config'"
echo "  2. Create exam template 'Final Examination Template'"
echo "  3. Add 'Last Ping Time' indicator 'Network Quality Monitor' to the template"
echo "  4. Create user account 'exam.coordinator' with Exam Administrator role"
