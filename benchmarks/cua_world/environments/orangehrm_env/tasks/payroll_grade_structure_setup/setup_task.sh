#!/bin/bash
# Pre-task setup for payroll_grade_structure_setup.
# - Removes any existing pay grades for the 3 task grades
# - Clears salary records for the 3 target employees
# - Creates the compensation framework document on the Desktop

set -euo pipefail
echo "=== Setting up payroll_grade_structure_setup task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/payroll_grade_structure_setup_result.json 2>/dev/null || true

# -------------------------------------------------------
# 2. Remove existing pay grades for task-specific grade names
# -------------------------------------------------------
log "Clearing target pay grades and their currency configurations..."

for GRADE_NAME in "Grade A - Senior" "Grade B - Mid-Level" "Grade C - Junior"; do
    PG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='${GRADE_NAME}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PG_ID" ]; then
        orangehrm_db_query "DELETE FROM ohrm_pay_grade_currency WHERE pay_grade_id=${PG_ID};" 2>/dev/null || true
        orangehrm_db_query "DELETE FROM ohrm_pay_grade WHERE id=${PG_ID};" 2>/dev/null || true
        log "Removed pay grade '${GRADE_NAME}' (id=$PG_ID)"
    fi
done

# -------------------------------------------------------
# 3. Resolve emp_numbers for target employees
# -------------------------------------------------------
EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP001' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP2=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP002' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP3=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP003' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EMP1" ]; then EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='James' AND emp_lastname='Anderson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi
if [ -z "$EMP2" ]; then EMP2=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Sarah' AND emp_lastname='Mitchell' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi
if [ -z "$EMP3" ]; then EMP3=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='David' AND emp_lastname='Nguyen' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi

log "EMP001 James Anderson: $EMP1"
log "EMP002 Sarah Mitchell: $EMP2"
log "EMP003 David Nguyen:   $EMP3"

# -------------------------------------------------------
# 4. Clear salary records for these employees
# -------------------------------------------------------
for EMPNUM in "$EMP1" "$EMP2" "$EMP3"; do
    if [ -n "$EMPNUM" ]; then
        orangehrm_db_query "DELETE FROM hs_hr_emp_basicsalary WHERE emp_number=${EMPNUM};" 2>/dev/null || true
        log "Cleared salary record for emp_number=$EMPNUM"
    fi
done

# -------------------------------------------------------
# 5. Ensure USD currency exists in system
# -------------------------------------------------------
USD_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_currency WHERE currency_id='USD';" | tr -d '[:space:]')
if [ "${USD_EXISTS:-0}" -eq "0" ]; then
    orangehrm_db_query "INSERT INTO hs_hr_currency (currency_id, currency_name) VALUES ('USD', 'United States Dollar');" 2>/dev/null || true
    log "Added USD currency"
fi

# -------------------------------------------------------
# 6. Record baseline
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
BASELINE_GRADES=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_pay_grade;" | tr -d '[:space:]')
echo "${BASELINE_GRADES:-0}" > /tmp/initial_grade_count.txt
log "Baseline pay grade count: $BASELINE_GRADES"

# -------------------------------------------------------
# 7. Create the compensation framework document on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/compensation_framework_q3.txt" << 'FRAMEWORK'
CLEARPATH FINANCIAL SERVICES — Q3 2025 COMPENSATION FRAMEWORK
==============================================================
Approved by: Compensation Committee
Effective:   2025-07-01
Prepared by: Total Rewards Team

INSTRUCTIONS FOR PAYROLL ADMINISTRATOR:
  1. Go to Admin > Pay Grades in OrangeHRM and create the grades below
  2. For each grade, add the USD salary band (minimum and maximum)
  3. Navigate to each employee's PIM profile > Salary tab and assign their grade and salary

----------------------------------------------------------------------
PAY GRADES TO CREATE
----------------------------------------------------------------------
| Grade Name           | Min Salary (USD) | Max Salary (USD) |
|----------------------|-----------------|-----------------|
| Grade A - Senior     |      90,000     |     140,000     |
| Grade B - Mid-Level  |      60,000     |      90,000     |
| Grade C - Junior     |      40,000     |      60,000     |

----------------------------------------------------------------------
EMPLOYEE SALARY ASSIGNMENTS
----------------------------------------------------------------------
| Employee Name        | ID     | Pay Grade           | Salary (USD) |
|----------------------|--------|---------------------|--------------|
| James Anderson       | EMP001 | Grade A - Senior    |    105,000   |
| Sarah Mitchell       | EMP002 | Grade B - Mid-Level |     75,000   |
| David Nguyen         | EMP003 | Grade C - Junior    |     50,000   |

----------------------------------------------------------------------
NOTE: Enter salaries in the PIM > Employee > Salary section.
Currency should be set to USD for all entries.
Pay Grade must be selected from the dropdown (must be created first).
----------------------------------------------------------------------
FRAMEWORK

chown ga:ga "$DESKTOP_DIR/compensation_framework_q3.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/compensation_framework_q3.txt"
log "Created compensation framework at $DESKTOP_DIR/compensation_framework_q3.txt"

# -------------------------------------------------------
# 8. Navigate to Pay Grades admin page
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/viewPayGrades"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png

echo "=== payroll_grade_structure_setup task setup complete ==="
echo "Target pay grades cleared. Salary records cleared for EMP001, EMP002, EMP003."
