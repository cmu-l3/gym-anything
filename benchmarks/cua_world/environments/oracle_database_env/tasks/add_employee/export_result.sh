#!/bin/bash
# Export script for Add Employee task
# Queries the database and saves verification data to JSON

echo "=== Exporting Add Employee Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ============================================================
# CRITICAL: Verify database is accessible before export
# ============================================================

echo "Verifying database connectivity..."
DB_CHECK=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT 'DB_OK' FROM DUAL;
EXIT;
SQLEOF" 2>&1)

if ! echo "$DB_CHECK" | grep -q "DB_OK"; then
    echo "ERROR: Database connection failed during export!"
    echo "Output: $DB_CHECK"

    # Create error result JSON
    cat > /tmp/add_employee_result.json << EOJSON
{
    "initial_employee_count": 0,
    "current_employee_count": 0,
    "initial_max_id": 0,
    "current_max_id": 0,
    "employee_found": false,
    "employee": {},
    "error": "Database connection failed during export",
    "db_error": "$(echo "$DB_CHECK" | grep "ORA-" | head -1 | sed 's/"/\\"/g')",
    "export_timestamp": "$(date -Iseconds)"
}
EOJSON
    chmod 644 /tmp/add_employee_result.json 2>/dev/null || true
    echo "Error result JSON saved"
    cat /tmp/add_employee_result.json
    exit 1
fi
echo "Database connection: OK"

# Get counts - read from protected files (only root can read)
INITIAL_COUNT=$(sudo cat /tmp/initial_employee_count 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
INITIAL_MAX_ID=$(sudo cat /tmp/initial_max_employee_id 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
CURRENT_COUNT=$(get_employee_count | grep -E '^[0-9]+$' | head -1)
CURRENT_MAX_ID=$(get_max_employee_id | grep -E '^[0-9]+$' | head -1)

# Sanitize values
INITIAL_COUNT=${INITIAL_COUNT:-0}
INITIAL_MAX_ID=${INITIAL_MAX_ID:-0}
CURRENT_COUNT=${CURRENT_COUNT:-0}
CURRENT_MAX_ID=${CURRENT_MAX_ID:-0}

echo "Employee count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"
echo "Max employee ID: initial=$INITIAL_MAX_ID, current=$CURRENT_MAX_ID"

# Check if the target employee was added using pipe-delimited output for reliable parsing
echo "Checking for employee 'Sarah Johnson' (case-insensitive)..."
EMPLOYEE_DATA=$(oracle_query "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400
SELECT employee_id || '|' || first_name || '|' || last_name || '|' || email || '|' ||
       NVL(phone_number,'N/A') || '|' || TO_CHAR(hire_date, 'YYYY-MM-DD') || '|' ||
       job_id || '|' || salary || '|' || NVL(TO_CHAR(manager_id),'N/A') || '|' || department_id
FROM employees
WHERE LOWER(TRIM(first_name))='sarah' AND LOWER(TRIM(last_name))='johnson'
ORDER BY employee_id DESC
FETCH FIRST 1 ROWS ONLY;" "hr" 2>/dev/null | grep '|' | head -1)

# NOTE: No partial matching or fallback to "any new employee"
# The verifier requires exact name match (Sarah Johnson) to pass
# This prevents exploitation via partial matches or unrelated employees
if [ -z "$EMPLOYEE_DATA" ]; then
    echo "Employee 'Sarah Johnson' not found with exact name match"
    echo "No fallback matching - verifier requires exact name"
fi

# Parse employee data if found
EMPLOYEE_FOUND="false"
EMP_ID=""
EMP_FNAME=""
EMP_LNAME=""
EMP_EMAIL=""
EMP_PHONE=""
EMP_HIRE_DATE=""
EMP_JOB_ID=""
EMP_SALARY=""
EMP_MGR_ID=""
EMP_DEPT_ID=""

if [ -n "$EMPLOYEE_DATA" ]; then
    EMPLOYEE_FOUND="true"
    # Parse pipe-delimited values
    EMP_ID=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f1 | tr -d ' ')
    EMP_FNAME=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f2 | sed 's/^ *//;s/ *$//')
    EMP_LNAME=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f3 | sed 's/^ *//;s/ *$//')
    EMP_EMAIL=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f4 | sed 's/^ *//;s/ *$//')
    EMP_PHONE=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f5 | sed 's/^ *//;s/ *$//')
    EMP_HIRE_DATE=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f6 | sed 's/^ *//;s/ *$//')
    EMP_JOB_ID=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f7 | sed 's/^ *//;s/ *$//')
    EMP_SALARY=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f8 | tr -d ' ')
    EMP_MGR_ID=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f9 | tr -d ' ')
    EMP_DEPT_ID=$(echo "$EMPLOYEE_DATA" | cut -d'|' -f10 | tr -d ' ')

    echo "Employee found: ID=$EMP_ID, Name='$EMP_FNAME $EMP_LNAME', Email=$EMP_EMAIL, Job=$EMP_JOB_ID, Salary=$EMP_SALARY, Dept=$EMP_DEPT_ID"
else
    echo "Employee 'Sarah Johnson' NOT found in database"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

EMP_FNAME_ESCAPED=$(escape_json "$EMP_FNAME")
EMP_LNAME_ESCAPED=$(escape_json "$EMP_LNAME")
EMP_EMAIL_ESCAPED=$(escape_json "$EMP_EMAIL")
EMP_PHONE_ESCAPED=$(escape_json "$EMP_PHONE")

# Create result JSON
cat > /tmp/add_employee_result.json << EOJSON
{
    "initial_employee_count": $INITIAL_COUNT,
    "current_employee_count": $CURRENT_COUNT,
    "initial_max_id": $INITIAL_MAX_ID,
    "current_max_id": $CURRENT_MAX_ID,
    "employee_found": $EMPLOYEE_FOUND,
    "employee": {
        "employee_id": "${EMP_ID:-}",
        "first_name": "${EMP_FNAME_ESCAPED:-}",
        "last_name": "${EMP_LNAME_ESCAPED:-}",
        "email": "${EMP_EMAIL_ESCAPED:-}",
        "phone_number": "${EMP_PHONE_ESCAPED:-}",
        "hire_date": "${EMP_HIRE_DATE:-}",
        "job_id": "${EMP_JOB_ID:-}",
        "salary": "${EMP_SALARY:-}",
        "manager_id": "${EMP_MGR_ID:-}",
        "department_id": "${EMP_DEPT_ID:-}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOJSON

chmod 644 /tmp/add_employee_result.json 2>/dev/null || true

echo ""
echo "Result JSON saved to /tmp/add_employee_result.json"
cat /tmp/add_employee_result.json

echo ""
echo "=== Export Complete ==="
