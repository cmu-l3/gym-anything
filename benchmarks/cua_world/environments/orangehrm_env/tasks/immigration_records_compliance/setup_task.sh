#!/bin/bash
# Pre-task setup for immigration_records_compliance.
# - Deletes any existing passport/immigration records for the 3 target employees
# - Creates the compliance audit notice on the Desktop

set -euo pipefail
echo "=== Setting up immigration_records_compliance task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/immigration_records_compliance_result.json 2>/dev/null || true

# -------------------------------------------------------
# 2. Resolve emp_number for each target employee
# -------------------------------------------------------
DAVID_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP003' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
JESSICA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP006' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
ROBERT_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP007' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

# Fallback by name if employee_id lookup fails
if [ -z "$DAVID_EMPNUM" ]; then
    DAVID_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='David' AND emp_lastname='Nguyen' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$JESSICA_EMPNUM" ]; then
    JESSICA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Jessica' AND emp_lastname='Liu' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$ROBERT_EMPNUM" ]; then
    ROBERT_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Robert' AND emp_lastname='Patel' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi

log "David Nguyen emp_number: $DAVID_EMPNUM"
log "Jessica Liu emp_number: $JESSICA_EMPNUM"
log "Robert Patel emp_number: $ROBERT_EMPNUM"

# -------------------------------------------------------
# 3. Delete existing immigration/passport records for these employees
# -------------------------------------------------------
for EMPNUM in "$DAVID_EMPNUM" "$JESSICA_EMPNUM" "$ROBERT_EMPNUM"; do
    if [ -n "$EMPNUM" ]; then
        orangehrm_db_query "DELETE FROM hs_hr_emp_passport WHERE emp_number=${EMPNUM};" 2>/dev/null || true
        log "Cleared passport records for emp_number=$EMPNUM"
    fi
done

# -------------------------------------------------------
# 4. Record baseline (timestamp + passport count = 0)
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "0" > /tmp/initial_passport_count.txt

# -------------------------------------------------------
# 5. Create the compliance audit notice on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/hr_compliance_audit_notice.txt" << 'NOTICE'
NORTHGATE MEDICAL CENTER — HR COMPLIANCE AUDIT NOTICE
======================================================
To:   HR Department
From: Compliance & Regulatory Affairs
Date: 2026-03-08
Re:   Annual Immigration Document Entry — URGENT

The Joint Commission audit requires that all international staff members
have their passport information entered into OrangeHRM under each
employee's PIM profile > Immigration section BEFORE the audit date.

The following employees are flagged as MISSING immigration records.
Please enter their passport details into OrangeHRM immediately.

Navigate to: PIM > Employee List > [Employee Name] > Immigration tab

----------------------------------------------------------------------
EMPLOYEE 1: David Nguyen  (Employee ID: EMP003)
----------------------------------------------------------------------
  Document Type  : Passport
  Passport No.   : VNB456123
  Issued Date    : 2022-03-15
  Expiry Date    : 2032-03-14
  Country Issued : Vietnam

----------------------------------------------------------------------
EMPLOYEE 2: Jessica Liu  (Employee ID: EMP006)
----------------------------------------------------------------------
  Document Type  : Passport
  Passport No.   : EA3456789
  Issued Date    : 2023-01-10
  Expiry Date    : 2033-01-09
  Country Issued : China

----------------------------------------------------------------------
EMPLOYEE 3: Robert Patel  (Employee ID: EMP007)
----------------------------------------------------------------------
  Document Type  : Passport
  Passport No.   : K3812456
  Issued Date    : 2021-07-20
  Expiry Date    : 2031-07-19
  Country Issued : India

----------------------------------------------------------------------
ACTION REQUIRED: Enter all three passport records into OrangeHRM
before end of business today. Failure to do so will result in an
audit finding.
----------------------------------------------------------------------
NOTICE

chown ga:ga "$DESKTOP_DIR/hr_compliance_audit_notice.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/hr_compliance_audit_notice.txt"
log "Created compliance audit notice at $DESKTOP_DIR/hr_compliance_audit_notice.txt"

# -------------------------------------------------------
# 6. Navigate to PIM employee list to give agent a starting context
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/pim/viewEmployeeList"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== immigration_records_compliance task setup complete ==="
echo "Employees: David Nguyen (EMP003), Jessica Liu (EMP006), Robert Patel (EMP007)"
echo "All existing passport records deleted. Agent must enter 3 passport records."
