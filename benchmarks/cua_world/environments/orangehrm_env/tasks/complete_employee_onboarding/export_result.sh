#!/bin/bash
# Export current state for complete_employee_onboarding verification.

set -euo pipefail
echo "=== Exporting complete_employee_onboarding results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/complete_employee_onboarding_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

CURRENT_YEAR=$(date +%Y)

# -------------------------------------------------------
# Lookup Alex Chen (EMP021) — try by employee_id first, then by name
# -------------------------------------------------------
ALEX_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP021' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
if [ -z "$ALEX_EMPNUM" ]; then
    ALEX_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Alex' AND emp_lastname='Chen' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
ALEX_EXISTS=$([ -n "$ALEX_EMPNUM" ] && echo "true" || echo "false")
log "Alex Chen: empnum=$ALEX_EMPNUM exists=$ALEX_EXISTS"

# -------------------------------------------------------
# Lookup Maria Santos (EMP022)
# -------------------------------------------------------
MARIA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP022' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
if [ -z "$MARIA_EMPNUM" ]; then
    MARIA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Maria' AND emp_lastname='Santos' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
MARIA_EXISTS=$([ -n "$MARIA_EMPNUM" ] && echo "true" || echo "false")
log "Maria Santos: empnum=$MARIA_EMPNUM exists=$MARIA_EXISTS"

# -------------------------------------------------------
# Helper functions
# -------------------------------------------------------
get_employee_dept() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "UNASSIGNED"; return; }
    orangehrm_db_query "
        SELECT COALESCE(s.name, 'UNASSIGNED')
        FROM hs_hr_employee e
        LEFT JOIN ohrm_subunit s ON e.work_unit = s.id
        WHERE e.emp_number=${empnum} AND e.purged_at IS NULL
        LIMIT 1;
    " | tr -d '[:space:]'
}

count_emergency_contacts() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "0"; return; }
    orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_emp_emergency_contacts WHERE emp_number=${empnum};" | tr -d '[:space:]'
}

get_annual_leave_days() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "0"; return; }
    local al_id
    al_id=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Annual Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')
    [ -z "$al_id" ] && { echo "0"; return; }
    orangehrm_db_query "
        SELECT COALESCE(SUM(no_of_days),0)
        FROM ohrm_leave_entitlement
        WHERE emp_number=${empnum} AND leave_type_id=${al_id}
          AND deleted=0 AND to_date >= '${CURRENT_YEAR}-01-01'
          AND from_date <= '${CURRENT_YEAR}-12-31';
    " | tr -d '[:space:]'
}

# -------------------------------------------------------
# Gather data for Alex Chen
# -------------------------------------------------------
ALEX_DEPT=$(get_employee_dept "$ALEX_EMPNUM")
ALEX_EC=$(count_emergency_contacts "$ALEX_EMPNUM")
ALEX_AL=$(get_annual_leave_days "$ALEX_EMPNUM")
log "Alex Chen: dept=$ALEX_DEPT ec=$ALEX_EC al_days=$ALEX_AL"

# -------------------------------------------------------
# Gather data for Maria Santos
# -------------------------------------------------------
MARIA_DEPT=$(get_employee_dept "$MARIA_EMPNUM")
MARIA_EC=$(count_emergency_contacts "$MARIA_EMPNUM")
MARIA_AL=$(get_annual_leave_days "$MARIA_EMPNUM")
log "Maria Santos: dept=$MARIA_DEPT ec=$MARIA_EC al_days=$MARIA_AL"

# -------------------------------------------------------
# Write JSON result
# -------------------------------------------------------
safe_write_result "{
  \"alex_exists\": ${ALEX_EXISTS},
  \"alex_dept\": \"${ALEX_DEPT}\",
  \"alex_ec_count\": ${ALEX_EC:-0},
  \"alex_al_days\": ${ALEX_AL:-0},
  \"maria_exists\": ${MARIA_EXISTS},
  \"maria_dept\": \"${MARIA_DEPT}\",
  \"maria_ec_count\": ${MARIA_EC:-0},
  \"maria_al_days\": ${MARIA_AL:-0}
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
