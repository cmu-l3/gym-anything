#!/bin/bash
# Export department restructure state for verification.

set -euo pipefail
echo "=== Exporting dept_restructure_workforce_reallocation results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/dept_restructure_workforce_reallocation_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

# -------------------------------------------------------
# Check for new sub-units
# -------------------------------------------------------
BACKEND_ID=$(orangehrm_db_query "SELECT id FROM ohrm_subunit WHERE name='Engineering - Backend Systems' LIMIT 1;" | tr -d '[:space:]')
RESEARCH_ID=$(orangehrm_db_query "SELECT id FROM ohrm_subunit WHERE name='Engineering - Applied Research' LIMIT 1;" | tr -d '[:space:]')

BACKEND_EXISTS=$([ -n "$BACKEND_ID" ] && echo "true" || echo "false")
RESEARCH_EXISTS=$([ -n "$RESEARCH_ID" ] && echo "true" || echo "false")

log "Engineering - Backend Systems: id=$BACKEND_ID exists=$BACKEND_EXISTS"
log "Engineering - Applied Research: id=$RESEARCH_ID exists=$RESEARCH_EXISTS"

# -------------------------------------------------------
# Resolve emp_numbers
# -------------------------------------------------------
EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP001' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP9=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP009' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP13=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP013' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EMP1" ]; then
    EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='James' AND emp_lastname='Anderson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$EMP9" ]; then
    EMP9=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Christopher' AND emp_lastname='Williams' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$EMP13" ]; then
    EMP13=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Daniel' AND emp_lastname='Wilson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi

# -------------------------------------------------------
# Get current department assignment for each employee
# -------------------------------------------------------
get_employee_dept_name() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "UNASSIGNED"; return; }
    orangehrm_db_query "
        SELECT COALESCE(s.name, 'UNASSIGNED')
        FROM hs_hr_employee e
        LEFT JOIN ohrm_subunit s ON e.work_station = s.id
        WHERE e.emp_number=${empnum} AND e.purged_at IS NULL
        LIMIT 1;
    " | tr -d '\n' | xargs
}

JAMES_DEPT=$(get_employee_dept_name "$EMP1")
CHRIS_DEPT=$(get_employee_dept_name "$EMP9")
DANIEL_DEPT=$(get_employee_dept_name "$EMP13")

log "James Anderson   dept='$JAMES_DEPT'"
log "Christopher Williams dept='$CHRIS_DEPT'"
log "Daniel Wilson    dept='$DANIEL_DEPT'"

# -------------------------------------------------------
# Current sub-unit count
# -------------------------------------------------------
CURRENT_SUBUNIT_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_subunit;" | tr -d '[:space:]')
INITIAL_COUNT=$(cat /tmp/initial_subunit_count.txt 2>/dev/null || echo "0")

log "Sub-unit count: initial=$INITIAL_COUNT current=$CURRENT_SUBUNIT_COUNT"

# -------------------------------------------------------
# Write result
# -------------------------------------------------------
safe_write_result "{
  \"backend_subunit_exists\": ${BACKEND_EXISTS},
  \"backend_subunit_id\": \"${BACKEND_ID}\",
  \"research_subunit_exists\": ${RESEARCH_EXISTS},
  \"research_subunit_id\": \"${RESEARCH_ID}\",
  \"james_dept\": \"${JAMES_DEPT}\",
  \"chris_dept\": \"${CHRIS_DEPT}\",
  \"daniel_dept\": \"${DANIEL_DEPT}\",
  \"initial_subunit_count\": ${INITIAL_COUNT},
  \"current_subunit_count\": ${CURRENT_SUBUNIT_COUNT}
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
