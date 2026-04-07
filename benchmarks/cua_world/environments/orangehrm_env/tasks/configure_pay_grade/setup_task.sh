#!/bin/bash
set -e
echo "=== Setting up configure_pay_grade task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrangeHRM to be available
wait_for_http "$ORANGEHRM_URL" 120

# 1. Clean up any prior "Grade HC-4" pay grade to ensure clean state
# We need to delete from ohrm_pay_grade_currency first due to foreign keys, then ohrm_pay_grade
log "Cleaning up previous 'Grade HC-4' entries..."
orangehrm_db_query "DELETE pgc FROM ohrm_pay_grade_currency pgc INNER JOIN ohrm_pay_grade pg ON pgc.pay_grade_id = pg.id WHERE pg.name = 'Grade HC-4';" || true
orangehrm_db_query "DELETE FROM ohrm_pay_grade WHERE name = 'Grade HC-4';" || true

# 2. Record initial state for anti-gaming verification
# We capture the current maximum ID. The new record must have an ID greater than this.
MAX_PG_ID=$(orangehrm_db_query "SELECT COALESCE(MAX(id), 0) FROM ohrm_pay_grade;" | tr -d '[:space:]')
echo "$MAX_PG_ID" > /tmp/initial_max_paygrade_id.txt
log "Initial max pay grade ID: $MAX_PG_ID"

# 3. Launch Firefox logged in to OrangeHRM Pay Grades page
# Target URL: /web/index.php/admin/viewPayGrades (or similar, URL often changes slightly in versions, usually .../admin/payGrade)
# In 5.x it is often accessed via Admin module. We'll land on the list page.
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/viewPayGrades"
ensure_orangehrm_logged_in "$TARGET_URL"

# 4. Take initial state screenshot
sleep 3
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured"

echo "=== Task setup complete ==="