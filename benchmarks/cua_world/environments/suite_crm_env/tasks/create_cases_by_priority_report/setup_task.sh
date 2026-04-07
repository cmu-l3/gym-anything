#!/bin/bash
echo "=== Setting up create_cases_by_priority_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any existing reports with the target name to ensure a blank slate
echo "Cleaning up any pre-existing reports with target name..."
suitecrm_db_query "UPDATE aor_reports SET deleted=1 WHERE name='Active Cases by Priority'"

# Record initial report count
INITIAL_REPORT_COUNT=$(suitecrm_count "aor_reports" "deleted=0")
echo "Initial report count: $INITIAL_REPORT_COUNT"
echo "$INITIAL_REPORT_COUNT" > /tmp/initial_report_count.txt
chmod 666 /tmp/initial_report_count.txt 2>/dev/null || true

# Ensure we are logged into SuiteCRM and navigate to Reports module (AOR_Reports)
echo "Logging in and navigating to Reports module..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=AOR_Reports&action=index"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="