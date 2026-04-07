#!/bin/bash
# Export project portfolio and timesheet state for verification.

set -euo pipefail
echo "=== Exporting project_timesheet_portfolio results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/project_timesheet_portfolio_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

# -------------------------------------------------------
# Check client (customer) existence
# -------------------------------------------------------
RIVERSIDE_ID=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='Riverside Community Foundation' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')
METRO_ID=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='Metro School District' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')

RIVERSIDE_EXISTS=$([ -n "$RIVERSIDE_ID" ] && echo "true" || echo "false")
METRO_EXISTS=$([ -n "$METRO_ID" ] && echo "true" || echo "false")

log "Riverside Foundation: id=$RIVERSIDE_ID exists=$RIVERSIDE_EXISTS"
log "Metro School District: id=$METRO_ID exists=$METRO_EXISTS"

# -------------------------------------------------------
# Check project existence
# -------------------------------------------------------
AFTERSCHOOL_ID=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE name='After-School Program Expansion' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')
DIGITAL_ID=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE name='Digital Literacy Initiative' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')

AFTERSCHOOL_EXISTS=$([ -n "$AFTERSCHOOL_ID" ] && echo "true" || echo "false")
DIGITAL_EXISTS=$([ -n "$DIGITAL_ID" ] && echo "true" || echo "false")

log "After-School Program Expansion: id=$AFTERSCHOOL_ID exists=$AFTERSCHOOL_EXISTS"
log "Digital Literacy Initiative: id=$DIGITAL_ID exists=$DIGITAL_EXISTS"

# -------------------------------------------------------
# Check project activities
# -------------------------------------------------------
PLANNING_EXISTS="false"
OUTREACH_EXISTS="false"
CURRICULUM_EXISTS="false"
TRAINING_EXISTS="false"

if [ -n "$AFTERSCHOOL_ID" ]; then
    P_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_activity WHERE project_id=${AFTERSCHOOL_ID} AND name='Program Planning' AND is_deleted=0;" | tr -d '[:space:]')
    O_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_activity WHERE project_id=${AFTERSCHOOL_ID} AND name='Community Outreach' AND is_deleted=0;" | tr -d '[:space:]')
    PLANNING_EXISTS=$([ "${P_COUNT:-0}" -gt "0" ] && echo "true" || echo "false")
    OUTREACH_EXISTS=$([ "${O_COUNT:-0}" -gt "0" ] && echo "true" || echo "false")
fi

if [ -n "$DIGITAL_ID" ]; then
    C_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_activity WHERE project_id=${DIGITAL_ID} AND name='Curriculum Development' AND is_deleted=0;" | tr -d '[:space:]')
    T_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_activity WHERE project_id=${DIGITAL_ID} AND name='Instructor Training' AND is_deleted=0;" | tr -d '[:space:]')
    CURRICULUM_EXISTS=$([ "${C_COUNT:-0}" -gt "0" ] && echo "true" || echo "false")
    TRAINING_EXISTS=$([ "${T_COUNT:-0}" -gt "0" ] && echo "true" || echo "false")
fi

log "Activities: Planning=$PLANNING_EXISTS Outreach=$OUTREACH_EXISTS Curriculum=$CURRICULUM_EXISTS Training=$TRAINING_EXISTS"

# -------------------------------------------------------
# Resolve employee emp_numbers
# -------------------------------------------------------
EMP5=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP005' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP15=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP015' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EMP5" ]; then EMP5=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Michael' AND emp_lastname='Thompson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi
if [ -z "$EMP15" ]; then EMP15=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Kevin' AND emp_lastname='Hernandez' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi

# -------------------------------------------------------
# Check timesheets for target week (April 7-11, 2025)
# -------------------------------------------------------
get_timesheet_total_hours() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "0"; return; }
    orangehrm_db_query "
        SELECT COALESCE(SUM(ti.duration), 0)
        FROM ohrm_timesheet_item ti
        JOIN ohrm_timesheet ts ON ti.timesheet_id = ts.timesheet_id
        WHERE ts.employee_id = ${empnum}
          AND ti.date BETWEEN '2025-04-07' AND '2025-04-11';
    " 2>/dev/null | tr -d '[:space:]'
}

MICHAEL_HOURS=$(get_timesheet_total_hours "$EMP5")
KEVIN_HOURS=$(get_timesheet_total_hours "$EMP15")

# Check if timesheets exist at all for target week
get_timesheet_count() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "0"; return; }
    orangehrm_db_query "
        SELECT COUNT(DISTINCT ts.timesheet_id)
        FROM ohrm_timesheet ts
        WHERE ts.employee_id = ${empnum}
          AND ts.start_date <= '2025-04-11'
          AND ts.end_date >= '2025-04-07';
    " 2>/dev/null | tr -d '[:space:]'
}

MICHAEL_TS_COUNT=$(get_timesheet_count "$EMP5")
KEVIN_TS_COUNT=$(get_timesheet_count "$EMP15")

log "Michael Thompson: timesheet_count=$MICHAEL_TS_COUNT total_hours=$MICHAEL_HOURS"
log "Kevin Hernandez:  timesheet_count=$KEVIN_TS_COUNT total_hours=$KEVIN_HOURS"

# -------------------------------------------------------
# Write result
# -------------------------------------------------------
safe_write_result "{
  \"riverside_exists\": ${RIVERSIDE_EXISTS},
  \"metro_exists\": ${METRO_EXISTS},
  \"afterschool_exists\": ${AFTERSCHOOL_EXISTS},
  \"digital_exists\": ${DIGITAL_EXISTS},
  \"activity_planning_exists\": ${PLANNING_EXISTS},
  \"activity_outreach_exists\": ${OUTREACH_EXISTS},
  \"activity_curriculum_exists\": ${CURRICULUM_EXISTS},
  \"activity_training_exists\": ${TRAINING_EXISTS},
  \"michael_timesheet_count\": ${MICHAEL_TS_COUNT:-0},
  \"michael_total_hours\": ${MICHAEL_HOURS:-0},
  \"kevin_timesheet_count\": ${KEVIN_TS_COUNT:-0},
  \"kevin_total_hours\": ${KEVIN_HOURS:-0}
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
