#!/bin/bash
# Export immigration records state for verification.

set -euo pipefail
echo "=== Exporting immigration_records_compliance results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/immigration_records_compliance_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

# -------------------------------------------------------
# Resolve emp_numbers (by ID then by name fallback)
# -------------------------------------------------------
DAVID_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP003' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
JESSICA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP006' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
ROBERT_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP007' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

if [ -z "$DAVID_EMPNUM" ]; then
    DAVID_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='David' AND emp_lastname='Nguyen' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$JESSICA_EMPNUM" ]; then
    JESSICA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Jessica' AND emp_lastname='Liu' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$ROBERT_EMPNUM" ]; then
    ROBERT_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Robert' AND emp_lastname='Patel' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi

log "David=$DAVID_EMPNUM Jessica=$JESSICA_EMPNUM Robert=$ROBERT_EMPNUM"

# -------------------------------------------------------
# Helper: get passport info for an employee
# Returns: passport_number|expiry_date|issue_date (or empty)
# -------------------------------------------------------
get_passport_info() {
    local empnum="$1"
    [ -z "$empnum" ] && { echo "||"; return; }
    orangehrm_db_query "
        SELECT COALESCE(ep_passport_num,''), COALESCE(DATE_FORMAT(ep_passportexpiredate,'%Y-%m-%d'),''), COALESCE(DATE_FORMAT(ep_passportissueddate,'%Y-%m-%d'),'')
        FROM hs_hr_emp_passport
        WHERE emp_number=${empnum}
        ORDER BY ep_seqno DESC
        LIMIT 1;
    " 2>/dev/null | tr '\t' '|' | tr -d '\n'
}

# -------------------------------------------------------
# Query each employee's passport data
# -------------------------------------------------------
DAVID_PP=$(get_passport_info "$DAVID_EMPNUM")
JESSICA_PP=$(get_passport_info "$JESSICA_EMPNUM")
ROBERT_PP=$(get_passport_info "$ROBERT_EMPNUM")

# Parse fields
DAVID_NUM=$(echo "$DAVID_PP" | cut -d'|' -f1 | xargs)
DAVID_EXP=$(echo "$DAVID_PP" | cut -d'|' -f2 | xargs)
DAVID_ISS=$(echo "$DAVID_PP" | cut -d'|' -f3 | xargs)

JESSICA_NUM=$(echo "$JESSICA_PP" | cut -d'|' -f1 | xargs)
JESSICA_EXP=$(echo "$JESSICA_PP" | cut -d'|' -f2 | xargs)
JESSICA_ISS=$(echo "$JESSICA_PP" | cut -d'|' -f3 | xargs)

ROBERT_NUM=$(echo "$ROBERT_PP" | cut -d'|' -f1 | xargs)
ROBERT_EXP=$(echo "$ROBERT_PP" | cut -d'|' -f2 | xargs)
ROBERT_ISS=$(echo "$ROBERT_PP" | cut -d'|' -f3 | xargs)

log "David Nguyen  passport: num=$DAVID_NUM exp=$DAVID_EXP iss=$DAVID_ISS"
log "Jessica Liu   passport: num=$JESSICA_NUM exp=$JESSICA_EXP iss=$JESSICA_ISS"
log "Robert Patel  passport: num=$ROBERT_NUM exp=$ROBERT_EXP iss=$ROBERT_ISS"

# -------------------------------------------------------
# Determine if records exist
# -------------------------------------------------------
DAVID_HAS=$([ -n "$DAVID_NUM" ] && echo "true" || echo "false")
JESSICA_HAS=$([ -n "$JESSICA_NUM" ] && echo "true" || echo "false")
ROBERT_HAS=$([ -n "$ROBERT_NUM" ] && echo "true" || echo "false")

# -------------------------------------------------------
# Write result JSON
# -------------------------------------------------------
safe_write_result "{
  \"david_has_passport\": ${DAVID_HAS},
  \"david_passport_no\": \"${DAVID_NUM}\",
  \"david_expiry\": \"${DAVID_EXP}\",
  \"david_issue\": \"${DAVID_ISS}\",
  \"jessica_has_passport\": ${JESSICA_HAS},
  \"jessica_passport_no\": \"${JESSICA_NUM}\",
  \"jessica_expiry\": \"${JESSICA_EXP}\",
  \"jessica_issue\": \"${JESSICA_ISS}\",
  \"robert_has_passport\": ${ROBERT_HAS},
  \"robert_passport_no\": \"${ROBERT_NUM}\",
  \"robert_expiry\": \"${ROBERT_EXP}\",
  \"robert_issue\": \"${ROBERT_ISS}\"
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
