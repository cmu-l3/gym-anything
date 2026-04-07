#!/bin/bash
echo "=== Setting up customize_contacts_list_view task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Ensure a clean state by removing any existing custom list view definitions for Contacts
echo "Cleaning up any existing custom layouts for Contacts..."
docker exec suitecrm-app rm -f /var/www/html/custom/modules/Contacts/metadata/listviewdefs.php

# 3. Mark the current end of the Apache access log
# This allows us to verify the agent actually used the UI to save the layout later
LOG_LINES=$(docker exec suitecrm-app wc -l /var/log/apache2/access.log | awk '{print $1}' 2>/dev/null || echo "0")
echo "$LOG_LINES" > /tmp/apache_log_start_line.txt
echo "Baseline Apache log line count: $LOG_LINES"

# 4. Ensure logged in and navigate to the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== customize_contacts_list_view task setup complete ==="
echo "Agent should navigate to Admin -> Studio -> Contacts -> Layouts -> List View"