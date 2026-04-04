#!/bin/bash
# Export script for Create Requester task
set -e

echo "=== Exporting Task Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_requester_count.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
scrot /tmp/task_final.png 2>/dev/null || true

# 2. Verify Data via Database
# We extract the created user details into a JSON object
TARGET_EMAIL="margaret.chen@pinnacletech.com"

# SQL to fetch details of the user with target email
# Returns pipe-separated values: FirstName|LastName|Phone|Mobile|DeptName|JobTitle|EmpID|CreatedTime
# Note: Timestamps in SDP are often BigInt (milliseconds)
SQL_QUERY="
SELECT 
    au.FIRST_NAME || '|' || 
    au.LAST_NAME || '|' || 
    COALESCE(aci.LANDLINE, '') || '|' || 
    COALESCE(aci.MOBILE, '') || '|' || 
    COALESCE(dd.DEPTNAME, '') || '|' || 
    COALESCE(rd.JOBTITLE, '') || '|' || 
    COALESCE(rd.EMPLOYEEID, '') || '|' || 
    au.CREATEDTIME
FROM AaaUser au
JOIN AaaUserContactInfo auci ON au.USER_ID = auci.USER_ID
JOIN AaaContactInfo aci ON auci.CONTACTINFO_ID = aci.CONTACTINFO_ID
JOIN SDUser sdu ON au.USER_ID = sdu.USERID
LEFT JOIN DepartmentDefinition dd ON sdu.DEPTID = dd.DEPTID
LEFT JOIN RequesterDetails rd ON sdu.USERID = rd.USERID
WHERE aci.EMAILID = '$TARGET_EMAIL'
LIMIT 1;"

USER_DATA=$(sdp_db_exec "$SQL_QUERY")

# Get Current Total Count
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM SDUser sdu JOIN AaaUser au ON sdu.USERID=au.USER_ID WHERE sdu.STATUS='ACTIVE';")

# 3. Construct JSON Result
# If USER_DATA is empty, the user wasn't found
USER_FOUND="false"
if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
fi

# Parse the pipe-separated data safely
IFS='|' read -r FNAME LNAME PHONE MOBILE DEPT JOBTITLE EMPID CREATED_TIME <<< "$USER_DATA"

# Create JSON file
TEMP_JSON="/tmp/result_temp.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_requester_count": $INITIAL_COUNT,
    "current_requester_count": ${CURRENT_COUNT:-0},
    "user_found": $USER_FOUND,
    "user_data": {
        "email": "$TARGET_EMAIL",
        "first_name": "${FNAME:-}",
        "last_name": "${LNAME:-}",
        "phone": "${PHONE:-}",
        "mobile": "${MOBILE:-}",
        "department": "${DEPT:-}",
        "job_title": "${JOBTITLE:-}",
        "employee_id": "${EMPID:-}",
        "created_time": "${CREATED_TIME:-0}"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to export location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json