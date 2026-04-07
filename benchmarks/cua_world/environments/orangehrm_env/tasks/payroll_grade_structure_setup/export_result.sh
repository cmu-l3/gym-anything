#!/bin/bash
# Export payroll grade and salary state for verification.

set -euo pipefail
echo "=== Exporting payroll_grade_structure_setup results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/payroll_grade_structure_setup_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

# -------------------------------------------------------
# Helper: get pay grade USD range
# Returns: min_salary|max_salary (or |)
# -------------------------------------------------------
get_grade_usd_range() {
    local grade_name="$1"
    PG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='${grade_name}' LIMIT 1;" | tr -d '[:space:]')
    if [ -z "$PG_ID" ]; then
        echo "0|0"
        return
    fi
    ROW=$(orangehrm_db_query "
        SELECT COALESCE(min_salary,0), COALESCE(max_salary,0)
        FROM ohrm_pay_grade_currency
        WHERE pay_grade_id=${PG_ID} AND currency_id='USD'
        LIMIT 1;
    " 2>/dev/null | tr '\t' '|' | tr -d '\n')
    echo "${ROW:-0|0}"
}

# -------------------------------------------------------
# Check pay grade existence and USD ranges
# -------------------------------------------------------
PG_SENIOR_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='Grade A - Senior' LIMIT 1;" | tr -d '[:space:]')
PG_MID_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='Grade B - Mid-Level' LIMIT 1;" | tr -d '[:space:]')
PG_JUNIOR_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='Grade C - Junior' LIMIT 1;" | tr -d '[:space:]')

SENIOR_EXISTS=$([ -n "$PG_SENIOR_ID" ] && echo "true" || echo "false")
MID_EXISTS=$([ -n "$PG_MID_ID" ] && echo "true" || echo "false")
JUNIOR_EXISTS=$([ -n "$PG_JUNIOR_ID" ] && echo "true" || echo "false")

SENIOR_RANGE=$(get_grade_usd_range "Grade A - Senior")
MID_RANGE=$(get_grade_usd_range "Grade B - Mid-Level")
JUNIOR_RANGE=$(get_grade_usd_range "Grade C - Junior")

SENIOR_MIN=$(echo "$SENIOR_RANGE" | cut -d'|' -f1 | xargs)
SENIOR_MAX=$(echo "$SENIOR_RANGE" | cut -d'|' -f2 | xargs)
MID_MIN=$(echo "$MID_RANGE" | cut -d'|' -f1 | xargs)
MID_MAX=$(echo "$MID_RANGE" | cut -d'|' -f2 | xargs)
JUNIOR_MIN=$(echo "$JUNIOR_RANGE" | cut -d'|' -f1 | xargs)
JUNIOR_MAX=$(echo "$JUNIOR_RANGE" | cut -d'|' -f2 | xargs)

log "Grade A Senior: exists=$SENIOR_EXISTS id=$PG_SENIOR_ID min=$SENIOR_MIN max=$SENIOR_MAX"
log "Grade B Mid: exists=$MID_EXISTS id=$PG_MID_ID min=$MID_MIN max=$MID_MAX"
log "Grade C Junior: exists=$JUNIOR_EXISTS id=$PG_JUNIOR_ID min=$JUNIOR_MIN max=$JUNIOR_MAX"

# -------------------------------------------------------
# Resolve employee emp_numbers
# -------------------------------------------------------
EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP001' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP2=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP002' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP3=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP003' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EMP1" ]; then EMP1=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='James' AND emp_lastname='Anderson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi
if [ -z "$EMP2" ]; then EMP2=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Sarah' AND emp_lastname='Mitchell' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi
if [ -z "$EMP3" ]; then EMP3=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='David' AND emp_lastname='Nguyen' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'); fi

# -------------------------------------------------------
# Get salary info for each employee
# Returns: pay_grade_name|salary
# -------------------------------------------------------
get_emp_salary_info() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "|0"; return; }
    orangehrm_db_query "
        SELECT COALESCE(pg.name,''), COALESCE(s.ebsal_basic_salary,0)
        FROM hs_hr_emp_basicsalary s
        LEFT JOIN ohrm_pay_grade pg ON s.sal_grd_code = pg.id
        WHERE s.emp_number=${empnum}
        ORDER BY s.id DESC
        LIMIT 1;
    " 2>/dev/null | tr '\t' '|' | tr -d '\n'
}

JAMES_SAL=$(get_emp_salary_info "$EMP1")
SARAH_SAL=$(get_emp_salary_info "$EMP2")
DAVID_SAL=$(get_emp_salary_info "$EMP3")

JAMES_GRADE=$(echo "$JAMES_SAL" | cut -d'|' -f1 | xargs)
JAMES_AMT=$(echo "$JAMES_SAL" | cut -d'|' -f2 | xargs)
SARAH_GRADE=$(echo "$SARAH_SAL" | cut -d'|' -f1 | xargs)
SARAH_AMT=$(echo "$SARAH_SAL" | cut -d'|' -f2 | xargs)
DAVID_GRADE=$(echo "$DAVID_SAL" | cut -d'|' -f1 | xargs)
DAVID_AMT=$(echo "$DAVID_SAL" | cut -d'|' -f2 | xargs)

log "James Anderson: grade='$JAMES_GRADE' salary=$JAMES_AMT"
log "Sarah Mitchell: grade='$SARAH_GRADE' salary=$SARAH_AMT"
log "David Nguyen:   grade='$DAVID_GRADE' salary=$DAVID_AMT"

# -------------------------------------------------------
# Write result
# -------------------------------------------------------
safe_write_result "{
  \"grade_a_exists\": ${SENIOR_EXISTS},
  \"grade_a_min\": ${SENIOR_MIN:-0},
  \"grade_a_max\": ${SENIOR_MAX:-0},
  \"grade_b_exists\": ${MID_EXISTS},
  \"grade_b_min\": ${MID_MIN:-0},
  \"grade_b_max\": ${MID_MAX:-0},
  \"grade_c_exists\": ${JUNIOR_EXISTS},
  \"grade_c_min\": ${JUNIOR_MIN:-0},
  \"grade_c_max\": ${JUNIOR_MAX:-0},
  \"james_grade\": \"${JAMES_GRADE}\",
  \"james_salary\": ${JAMES_AMT:-0},
  \"sarah_grade\": \"${SARAH_GRADE}\",
  \"sarah_salary\": ${SARAH_AMT:-0},
  \"david_grade\": \"${DAVID_GRADE}\",
  \"david_salary\": ${DAVID_AMT:-0}
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
