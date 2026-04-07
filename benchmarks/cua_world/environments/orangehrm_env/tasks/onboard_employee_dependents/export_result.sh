#!/bin/bash
set -e
echo "=== Exporting Onboard Employee Dependents results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Results
# We need to construct a JSON object with the employee and dependent info

# Find James Holden
EMP_NUMBER=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='James' AND emp_lastname='Holden' AND purged_at IS NULL ORDER BY emp_number DESC LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

EMPLOYEE_FOUND="false"
DEPENDENTS_JSON="[]"

if [ -n "$EMP_NUMBER" ] && [ "$EMP_NUMBER" != "0" ]; then
    EMPLOYEE_FOUND="true"
    echo "Found James Holden (Emp Number: $EMP_NUMBER)"

    # Get Dependents using a complex query to format as JSON lines, then wrap them
    # Note: ohrm_emp_dependents table structure: emp_number, seqno, name, relationship_type, relationship, dob
    # We select name, relationship_type (or relationship if type is 'other'), and dob
    
    # Check column names carefully. In OrangeHRM 5.x:
    # Table: hs_hr_emp_dependents
    # Columns: emp_number, seqno, ede_name, ede_relationship_type, ede_relationship, ede_dob
    
    RAW_DEPS=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
        SELECT JSON_OBJECT(
            'name', ede_name,
            'relationship_type', ede_relationship_type,
            'relationship_other', ede_relationship,
            'dob', ede_dob
        )
        FROM hs_hr_emp_dependents
        WHERE emp_number = $EMP_NUMBER
    " 2>/dev/null)
    
    # Join lines with commas and wrap in brackets
    if [ -n "$RAW_DEPS" ]; then
        DEPENDENTS_JSON="[$(echo "$RAW_DEPS" | paste -sd, -)]"
    fi
else
    echo "James Holden not found in database."
fi

# 3. Create Result JSON
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use jq if available, otherwise manual construction
# Environment has jq installed via install_orangehrm.sh
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "employee_found": $EMPLOYEE_FOUND,
  "emp_number": "${EMP_NUMBER:-null}",
  "dependents": $DEPENDENTS_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so python script can read it if needed (though copy_from_env handles root)
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json