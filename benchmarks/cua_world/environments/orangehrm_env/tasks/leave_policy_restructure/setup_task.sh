#!/bin/bash
# Pre-task setup for leave_policy_restructure
# - Sets Finance employees' Annual Leave to 30 days (wrong; policy = 12)
# - Removes any existing Sick Leave for Finance employees
# - Soft-deletes 'Compensatory Time Off' leave type if it exists

set -euo pipefail
echo "=== Setting up leave_policy_restructure task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/leave_policy_restructure_result.json 2>/dev/null || true

CURRENT_YEAR=$(date +%Y)
log "Current year: $CURRENT_YEAR"

# -------------------------------------------------------
# 2. Get Finance emp_numbers (EMP003, EMP010, EMP017)
# -------------------------------------------------------
get_empnum() {
    orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='$1' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'
}
E3=$(get_empnum EMP003)   # David Nguyen     - Financial Analyst
E10=$(get_empnum EMP010)  # Amanda Davis     - Financial Analyst
E17=$(get_empnum EMP017)  # Brian Taylor     - Financial Analyst

if [ -z "$E3" ] || [ -z "$E10" ] || [ -z "$E17" ]; then
    echo "ERROR: One or more Finance employees not found"
    exit 1
fi
log "Finance emp_numbers: E3=$E3 E10=$E10 E17=$E17"

# -------------------------------------------------------
# 3. Get Annual Leave type ID
# -------------------------------------------------------
AL_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Annual Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')
if [ -z "$AL_ID" ]; then
    echo "ERROR: 'Annual Leave' leave type not found"
    exit 1
fi
log "Annual Leave type id=$AL_ID"

# -------------------------------------------------------
# 4. Get Sick Leave type ID
# -------------------------------------------------------
SL_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Sick Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')
if [ -z "$SL_ID" ]; then
    log "WARNING: Sick Leave type not found — will skip SL cleanup"
fi

# -------------------------------------------------------
# 5. Inject error: set Finance employees' Annual Leave to 30 days
# -------------------------------------------------------
log "Setting Finance employees' Annual Leave to 30 days (wrong)..."
for EMP in $E3 $E10 $E17; do
    # Update existing entitlement if any
    EXISTING=$(orangehrm_db_query "SELECT id FROM ohrm_leave_entitlement WHERE emp_number=${EMP} AND leave_type_id=${AL_ID} AND deleted=0 AND to_date >= '${CURRENT_YEAR}-01-01' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$EXISTING" ]; then
        orangehrm_db_query "UPDATE ohrm_leave_entitlement SET no_of_days=30 WHERE id=${EXISTING};" || true
        log "  Updated emp_number=${EMP} Annual Leave to 30 days (id=$EXISTING)"
    else
        # Insert new entitlement at 30 days
        orangehrm_db_query "INSERT INTO ohrm_leave_entitlement (emp_number, no_of_days, leave_type_id, from_date, to_date, credited_date, days_used, entitlement_type, deleted, created_by_id) VALUES (${EMP}, 30, ${AL_ID}, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1);" || true
        log "  Inserted emp_number=${EMP} Annual Leave 30 days"
    fi
done

# -------------------------------------------------------
# 6. Remove any Sick Leave for Finance employees (so agent must add it)
# -------------------------------------------------------
if [ -n "${SL_ID:-}" ]; then
    log "Removing Sick Leave entitlements for Finance employees..."
    orangehrm_db_query "UPDATE ohrm_leave_entitlement SET deleted=1 WHERE emp_number IN (${E3},${E10},${E17}) AND leave_type_id=${SL_ID} AND to_date >= '${CURRENT_YEAR}-01-01';" || true
fi

# -------------------------------------------------------
# 7. Remove 'Compensatory Time Off' leave type if it exists
# -------------------------------------------------------
orangehrm_db_query "UPDATE ohrm_leave_type SET deleted=1 WHERE name='Compensatory Time Off';" 2>/dev/null || true
log "Ensured 'Compensatory Time Off' leave type does not exist"

# -------------------------------------------------------
# 8. Record task start timestamp
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp 2>/dev/null || true
log "Task start timestamp recorded"

# -------------------------------------------------------
# 9. Navigate to Leave > Leave Types to give agent context
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/leave/leaveTypeList"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== leave_policy_restructure task setup complete ==="
echo "Finance employees (EMP003=$E3, EMP010=$E10, EMP017=$E17) now have 30-day Annual Leave"
echo "'Compensatory Time Off' leave type removed"
echo "Sick Leave for Finance employees cleared"
