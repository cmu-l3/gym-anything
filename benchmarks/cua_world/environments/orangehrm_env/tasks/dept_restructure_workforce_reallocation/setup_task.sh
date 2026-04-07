#!/bin/bash
# Pre-task setup for dept_restructure_workforce_reallocation.
# - Removes any prior sub-units named "Engineering - Backend Systems" or "Engineering - Applied Research"
# - Resets the 3 target employees back to the parent "Engineering" department
# - Creates the restructuring directive on the Desktop

set -euo pipefail
echo "=== Setting up dept_restructure_workforce_reallocation task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/dept_restructure_workforce_reallocation_result.json 2>/dev/null || true

# -------------------------------------------------------
# 2. Remove any prior sub-units with the new names (idempotent)
# -------------------------------------------------------
log "Removing any prior Engineering sub-units from previous runs..."
for SUNAME in "Engineering - Backend Systems" "Engineering - Applied Research"; do
    SU_ID=$(orangehrm_db_query "SELECT id FROM ohrm_subunit WHERE name='${SUNAME}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$SU_ID" ]; then
        # Reassign employees in this sub-unit to parent Engineering before deleting
        ENG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_subunit WHERE name='Engineering' LIMIT 1;" | tr -d '[:space:]')
        if [ -n "$ENG_ID" ]; then
            orangehrm_db_query "UPDATE hs_hr_employee SET work_station=${ENG_ID} WHERE work_station=${SU_ID};" 2>/dev/null || true
        fi
        # Delete the sub-unit (nested set — simplest: just delete the row; setup_orangehrm rebuilds tree as needed)
        orangehrm_db_query "DELETE FROM ohrm_subunit WHERE id=${SU_ID};" 2>/dev/null || true
        log "Removed sub-unit '${SUNAME}' (id=$SU_ID)"
    fi
done

# -------------------------------------------------------
# 3. Resolve emp_numbers for the 3 target employees
# -------------------------------------------------------
EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP001' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP9=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP009' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP13=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP013' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

# Fallback by name
if [ -z "$EMP1" ]; then
    EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='James' AND emp_lastname='Anderson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$EMP9" ]; then
    EMP9=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Christopher' AND emp_lastname='Williams' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$EMP13" ]; then
    EMP13=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Daniel' AND emp_lastname='Wilson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi

log "EMP001 (James Anderson) emp_number=$EMP1"
log "EMP009 (Christopher Williams) emp_number=$EMP9"
log "EMP013 (Daniel Wilson) emp_number=$EMP13"

# -------------------------------------------------------
# 4. Reset these employees to parent Engineering department
# -------------------------------------------------------
ENG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_subunit WHERE name='Engineering' LIMIT 1;" | tr -d '[:space:]')
log "Engineering subunit id=$ENG_ID"

if [ -n "$ENG_ID" ]; then
    for EMPNUM in "$EMP1" "$EMP9" "$EMP13"; do
        if [ -n "$EMPNUM" ]; then
            orangehrm_db_query "UPDATE hs_hr_employee SET work_station=${ENG_ID} WHERE emp_number=${EMPNUM};" 2>/dev/null || true
        fi
    done
    log "Reset 3 employees to Engineering (id=$ENG_ID)"
fi

# -------------------------------------------------------
# 5. Record baseline sub-unit count
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
BASELINE_SUBUNIT_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_subunit;" | tr -d '[:space:]')
echo "${BASELINE_SUBUNIT_COUNT:-0}" > /tmp/initial_subunit_count.txt
log "Baseline sub-unit count: $BASELINE_SUBUNIT_COUNT"

# -------------------------------------------------------
# 6. Create the restructuring directive on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/dept_restructure_directive.txt" << 'DIRECTIVE'
WESTBROOK UNIVERSITY — ACADEMIC DEPARTMENT RESTRUCTURING DIRECTIVE
==================================================================
To:    Director of Academic HR
From:  Provost Office
Date:  2026-03-08
Re:    Engineering Department Division — Faculty Governance Resolution #2026-14

Following the faculty senate vote of 2026-02-15, the Engineering department
is to be formally divided into two sub-units effective immediately.
Please implement the following changes in OrangeHRM (Admin > Organization > Sub Units),
then update each affected employee's department assignment.

----------------------------------------------------------------------
STEP 1: CREATE NEW SUB-UNITS UNDER "Engineering"
----------------------------------------------------------------------
Create these two sub-units as children of the existing "Engineering" unit:

  Sub-Unit Name: Engineering - Backend Systems
  Sub-Unit Name: Engineering - Applied Research

----------------------------------------------------------------------
STEP 2: REASSIGN EMPLOYEES TO NEW SUB-UNITS
----------------------------------------------------------------------
Update each employee's department in OrangeHRM (PIM > Employee > Job tab):

  James Anderson       (EMP001)  →  Engineering - Backend Systems
  Christopher Williams (EMP009)  →  Engineering - Backend Systems
  Daniel Wilson        (EMP013)  →  Engineering - Applied Research

----------------------------------------------------------------------
These changes must be reflected in OrangeHRM before the budget system
integration runs on 2026-03-15. Incomplete assignments will cause
payroll routing errors.
----------------------------------------------------------------------
DIRECTIVE

chown ga:ga "$DESKTOP_DIR/dept_restructure_directive.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/dept_restructure_directive.txt"
log "Created restructuring directive at $DESKTOP_DIR/dept_restructure_directive.txt"

# -------------------------------------------------------
# 7. Navigate to Sub Units admin page
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/viewOrganizationGeneralInformation"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png

echo "=== dept_restructure_workforce_reallocation task setup complete ==="
echo "Engineering sub-unit id=$ENG_ID, baseline sub-unit count=$BASELINE_SUBUNIT_COUNT"
echo "Employees reset to Engineering: EMP001, EMP009, EMP013"
