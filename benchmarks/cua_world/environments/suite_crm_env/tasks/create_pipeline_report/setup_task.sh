#!/bin/bash
echo "=== Setting up create_pipeline_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# 1. Verify the target report does not already exist and remove if it does
REPORT_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM aor_reports WHERE name='Weekly Pipeline by Stage' AND deleted=0" | tr -d '[:space:]')
if [ "$REPORT_EXISTS" -gt 0 ]; then
    echo "WARNING: Report 'Weekly Pipeline by Stage' already exists, removing..."
    suitecrm_db_query "UPDATE aor_reports SET deleted=1 WHERE name='Weekly Pipeline by Stage'"
fi

# 2. Record initial report count
INITIAL_REPORT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aor_reports WHERE deleted=0" | tr -d '[:space:]')
echo "Initial report count: $INITIAL_REPORT_COUNT"
echo "$INITIAL_REPORT_COUNT" > /tmp/initial_report_count.txt
chmod 666 /tmp/initial_report_count.txt 2>/dev/null || true

# 3. Ensure logged in and navigate to Home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_pipeline_report_initial.png

echo "=== create_pipeline_report task setup complete ==="
echo "Task: Create a new report 'Weekly Pipeline by Stage' targeting Opportunities."
echo "Agent should navigate to Reports, use the report builder, add fields, and apply grouping."