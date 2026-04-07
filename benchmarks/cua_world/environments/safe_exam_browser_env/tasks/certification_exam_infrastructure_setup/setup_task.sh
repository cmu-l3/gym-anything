#!/bin/bash
echo "=== Setting up certification_exam_infrastructure_setup task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json \
    /tmp/certification_exam_infrastructure_setup_result.json \
    /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline database state
record_baseline "certification_exam_infrastructure_setup"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent must set up complete certification exam infrastructure:"
echo "  1. Create exam configuration 'Professional Certification Lockdown' and configure settings"
echo "  2. Create exam template 'Proctored Certification Template' with 2 monitoring indicators"
echo "  3. Create and activate connection configuration 'Certification Center Link'"
echo "  4. Create and activate user account 'lead.proctor' with Exam Supporter role"
