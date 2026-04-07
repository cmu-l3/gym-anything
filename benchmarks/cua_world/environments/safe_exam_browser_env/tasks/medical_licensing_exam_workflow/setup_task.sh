#!/bin/bash
echo "=== Setting up medical_licensing_exam_workflow task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json \
    /tmp/medical_licensing_exam_workflow_result.json \
    /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline (captures current exam count, indicator count, user count)
record_baseline "medical_licensing_exam_workflow"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Assessment Tool quizzes available for import."
echo "Agent must:"
echo "  1. Import one exam from Assessment Tool"
echo "  2. Add 'Last Ping Time' indicator 'Latency Monitor' to the imported exam"
echo "  3. Add 'Warning-Log Counter' indicator 'Integrity Alert' to the imported exam"
echo "  4. Create user 'med.proctor' with Exam Supporter role"
