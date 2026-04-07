#!/bin/bash
echo "=== Exporting hire_candidate_setup_email results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query DB for Candidate Status
# We expect status to be 'HIRED' (or corresponding ID)
# Standard OrangeHRM: Hired status ID is often 8 or labeled 'Hired'
CANDIDATE_STATUS_ID=$(orangehrm_db_query "SELECT status FROM ohrm_job_candidate WHERE first_name='Elias' AND last_name='Thorne' LIMIT 1" | tr -d '[:space:]')
CANDIDATE_STATUS_LABEL=$(orangehrm_db_query "SELECT status_label FROM ohrm_job_candidate_status WHERE id='${CANDIDATE_STATUS_ID}' LIMIT 1" 2>/dev/null || echo "Unknown")

echo "Candidate Status ID: $CANDIDATE_STATUS_ID ($CANDIDATE_STATUS_LABEL)"

# Query DB for Employee Record
# Check if employee exists and get details
EMP_DATA_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
SELECT JSON_OBJECT(
    'exists', IF(COUNT(*) > 0, TRUE, FALSE),
    'emp_number', MAX(emp_number),
    'work_email', MAX(emp_work_email),
    'joined_date', MAX(joined_date),
    'first_name', MAX(emp_firstname),
    'last_name', MAX(emp_lastname)
)
FROM hs_hr_employee 
WHERE emp_firstname='Elias' AND emp_lastname='Thorne';
" 2>/dev/null)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "candidate_status_id": "$CANDIDATE_STATUS_ID",
    "candidate_status_label": "$CANDIDATE_STATUS_LABEL",
    "employee_data": $EMP_DATA_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="