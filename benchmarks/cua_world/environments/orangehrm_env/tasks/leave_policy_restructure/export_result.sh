#!/bin/bash
# Export current leave configuration state for leave_policy_restructure verification.

set -euo pipefail
echo "=== Exporting leave_policy_restructure results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/leave_policy_restructure_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

CURRENT_YEAR=$(date +%Y)

# -------------------------------------------------------
# Resolve emp_numbers for Finance employees
# -------------------------------------------------------
get_empnum() {
    orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='$1' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]'
}
E3=$(get_empnum EMP003)
E10=$(get_empnum EMP010)
E17=$(get_empnum EMP017)
log "Finance emp_numbers: $E3 $E10 $E17"

# -------------------------------------------------------
# Check whether 'Compensatory Time Off' leave type exists
# -------------------------------------------------------
COMP_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_leave_type WHERE name='Compensatory Time Off' AND deleted=0;" | tr -d '[:space:]')
COMP_EXISTS=$([ "${COMP_COUNT:-0}" -gt 0 ] && echo "true" || echo "false")
log "Compensatory Time Off exists: $COMP_EXISTS"

# -------------------------------------------------------
# Get Annual Leave type ID
# -------------------------------------------------------
AL_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Annual Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')
SL_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Sick Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')

# Helper: get active entitlement days for a given emp+leave_type
get_entitlement_days() {
    local emp="$1"
    local lt="$2"
    orangehrm_db_query "SELECT COALESCE(SUM(no_of_days),0) FROM ohrm_leave_entitlement WHERE emp_number=${emp} AND leave_type_id=${lt} AND deleted=0 AND to_date >= '${CURRENT_YEAR}-01-01' AND from_date <= '${CURRENT_YEAR}-12-31';" | tr -d '[:space:]'
}

# -------------------------------------------------------
# Annual Leave days for Finance employees (should be 12 each)
# -------------------------------------------------------
AL_E3=$(get_entitlement_days "$E3" "$AL_ID")
AL_E10=$(get_entitlement_days "$E10" "$AL_ID")
AL_E17=$(get_entitlement_days "$E17" "$AL_ID")
log "Annual Leave (Finance): EMP003=$AL_E3 EMP010=$AL_E10 EMP017=$AL_E17"

# -------------------------------------------------------
# Sick Leave days for Finance employees (should be 10 each)
# -------------------------------------------------------
if [ -n "${SL_ID:-}" ]; then
    SL_E3=$(get_entitlement_days "$E3" "$SL_ID")
    SL_E10=$(get_entitlement_days "$E10" "$SL_ID")
    SL_E17=$(get_entitlement_days "$E17" "$SL_ID")
else
    SL_E3=0; SL_E10=0; SL_E17=0
fi
log "Sick Leave (Finance): EMP003=$SL_E3 EMP010=$SL_E10 EMP017=$SL_E17"

# -------------------------------------------------------
# Write JSON result
# -------------------------------------------------------
safe_write_result "{
  \"comp_time_off_exists\": ${COMP_EXISTS},
  \"al_emp003_days\": ${AL_E3:-0},
  \"al_emp010_days\": ${AL_E10:-0},
  \"al_emp017_days\": ${AL_E17:-0},
  \"sl_emp003_days\": ${SL_E3:-0},
  \"sl_emp010_days\": ${SL_E10:-0},
  \"sl_emp017_days\": ${SL_E17:-0}
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
