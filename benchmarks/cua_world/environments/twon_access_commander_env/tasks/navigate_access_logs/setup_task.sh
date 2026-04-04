#!/bin/bash
echo "=== Setting up navigate_access_logs task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo

# Navigate to Access Logs page
launch_firefox_to "${AC_URL}/#/accessLog" 8

take_screenshot /tmp/task_navigate_access_logs_start.png
echo "=== Task navigate_access_logs setup complete ==="
