#!/bin/bash
set -euo pipefail
echo "=== Setting up configure_performance_kpis task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrangeHRM to be ready
wait_for_http "$ORANGEHRM_URL" 60

# 3. Clean up specific KPIs if they already exist (idempotency)
# We delete by name to ensure the agent has to create them
echo "Cleaning up any existing KPIs with target names..."
TARGET_NAMES=(
    "Code Quality and Review Standards"
    "On-Time Delivery of Sprint Tasks"
    "Technical Documentation"
    "Employee Retention Rate"
    "Compliance with Labor Regulations"
)

for name in "${TARGET_NAMES[@]}"; do
    orangehrm_db_query "UPDATE ohrm_kpi SET is_deleted=1 WHERE kpi_indicators='${name}';" 2>/dev/null || true
done

# 4. Verify Job Titles exist (Critical dependency)
# The setup_orangehrm.sh script seeds these, but we double check.
echo "Verifying job titles..."
if ! job_title_exists "Software Engineer"; then
    echo "Creating Software Engineer job title..."
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Software Engineer', 0);"
fi
if ! job_title_exists "HR Manager"; then
    echo "Creating HR Manager job title..."
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('HR Manager', 0);"
fi

# 5. Record initial KPI count (for anti-gaming delta check)
INITIAL_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_kpi WHERE is_deleted=0;" 2>/dev/null | tr -d '[:space:]')
echo "${INITIAL_COUNT:-0}" > /tmp/initial_kpi_count.txt
echo "Initial KPI count: ${INITIAL_COUNT:-0}"

# 6. Login and set initial state
# Navigate to Dashboard. The user is expected to navigate to Performance > Configure > KPIs
TARGET_URL="${ORANGEHRM_URL}/web/index.php/dashboard/index"
ensure_orangehrm_logged_in "$TARGET_URL"

# 7. Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="