#!/bin/bash
set -e
echo "=== Setting up create_export_science_exams task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Clean up target directory to prevent gaming
rm -rf /home/ga/Documents/ExamBackups 2>/dev/null || true
# Ensure Downloads folder is clean of old .seb files
rm -f /home/ga/Downloads/*.seb 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline using shared util if available
if type record_baseline >/dev/null 2>&1; then
    record_baseline "create_export_science_exams"
fi

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 5

# Ensure browser is maximized
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should create 3 Exam Configurations, configure them, and export their .seb files to ~/Documents/ExamBackups/"