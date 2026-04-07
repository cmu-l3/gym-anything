#!/bin/bash
# Pre-task setup for complete_employee_onboarding
# - Removes any existing records for the two new hires (Alex Chen, Maria Santos)
# - Creates the spec file on the Desktop with new hire details

set -euo pipefail
echo "=== Setting up complete_employee_onboarding task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/complete_employee_onboarding_result.json 2>/dev/null || true

CURRENT_YEAR=$(date +%Y)
log "Current year: $CURRENT_YEAR"

# -------------------------------------------------------
# 2. Remove any existing records for EMP021 (Alex Chen) and EMP022 (Maria Santos)
# -------------------------------------------------------
log "Purging any existing records for EMP021 / Alex Chen..."
EXISTING_E21=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP021' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
if [ -n "$EXISTING_E21" ]; then
    # Remove dependent records first
    orangehrm_db_query "DELETE FROM hs_hr_emp_emergency_contacts WHERE emp_number=${EXISTING_E21};" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_leave_entitlement WHERE emp_number=${EXISTING_E21};" 2>/dev/null || true
    orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE emp_number=${EXISTING_E21};" 2>/dev/null || true
    log "Purged existing EMP021 (emp_number=$EXISTING_E21)"
fi

# Also purge by name in case employee_id differs
EXISTING_ALEX=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Alex' AND emp_lastname='Chen' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
if [ -n "$EXISTING_ALEX" ]; then
    orangehrm_db_query "DELETE FROM hs_hr_emp_emergency_contacts WHERE emp_number=${EXISTING_ALEX};" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_leave_entitlement WHERE emp_number=${EXISTING_ALEX};" 2>/dev/null || true
    orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE emp_number=${EXISTING_ALEX};" 2>/dev/null || true
    log "Purged existing Alex Chen (emp_number=$EXISTING_ALEX)"
fi

log "Purging any existing records for EMP022 / Maria Santos..."
EXISTING_E22=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP022' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
if [ -n "$EXISTING_E22" ]; then
    orangehrm_db_query "DELETE FROM hs_hr_emp_emergency_contacts WHERE emp_number=${EXISTING_E22};" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_leave_entitlement WHERE emp_number=${EXISTING_E22};" 2>/dev/null || true
    orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE emp_number=${EXISTING_E22};" 2>/dev/null || true
    log "Purged existing EMP022 (emp_number=$EXISTING_E22)"
fi
EXISTING_MARIA=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Maria' AND emp_lastname='Santos' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
if [ -n "$EXISTING_MARIA" ]; then
    orangehrm_db_query "DELETE FROM hs_hr_emp_emergency_contacts WHERE emp_number=${EXISTING_MARIA};" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_leave_entitlement WHERE emp_number=${EXISTING_MARIA};" 2>/dev/null || true
    orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE emp_number=${EXISTING_MARIA};" 2>/dev/null || true
    log "Purged existing Maria Santos (emp_number=$EXISTING_MARIA)"
fi

# -------------------------------------------------------
# 3. Create the new hire spec file on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/new_hire_spec.txt" << EOF
NEW HIRE ONBOARDING SPECIFICATION
===================================
Prepared by: HR Department
Date: $(date +%Y-%m-%d)

Please add both employees below to OrangeHRM and complete all onboarding steps.

----------------------------------------------------------------------
EMPLOYEE 1
----------------------------------------------------------------------
First Name:   Alex
Last Name:    Chen
Employee ID:  EMP021
Job Title:    Marketing Specialist
Department:   Marketing
Work Email:   alex.chen@gymhrco.com
Work Phone:   310-555-0021

----------------------------------------------------------------------
EMPLOYEE 2
----------------------------------------------------------------------
First Name:   Maria
Last Name:    Santos
Employee ID:  EMP022
Job Title:    Financial Analyst
Department:   Finance
Work Email:   maria.santos@gymhrco.com
Work Phone:   415-555-0022

----------------------------------------------------------------------
REQUIRED FOR EACH EMPLOYEE (complete all steps):
  1. Create employee record in PIM with the Employee ID, name, work email, and work phone above
  2. Set the correct Job Title and Department on the employee profile
  3. Add at least one emergency contact (name, relationship, and phone number)
  4. Add an Annual Leave entitlement: 15 days for the ${CURRENT_YEAR} calendar year
----------------------------------------------------------------------
EOF

chown ga:ga "$DESKTOP_DIR/new_hire_spec.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/new_hire_spec.txt"
log "Created spec file at $DESKTOP_DIR/new_hire_spec.txt"

# -------------------------------------------------------
# 4. Record task start timestamp
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp 2>/dev/null || true
log "Task start timestamp recorded"

# -------------------------------------------------------
# 5. Navigate to PIM > Add Employee to give agent a starting context
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/pim/addEmployee"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== complete_employee_onboarding task setup complete ==="
echo "Spec file: $DESKTOP_DIR/new_hire_spec.txt"
echo "Agent must onboard: Alex Chen (EMP021, Marketing) and Maria Santos (EMP022, Finance)"
