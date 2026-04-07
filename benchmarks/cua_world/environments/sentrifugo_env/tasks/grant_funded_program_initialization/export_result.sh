#!/bin/bash
echo "=== Exporting grant_funded_program_initialization result ==="

source /workspace/scripts/task_utils.sh

# Record end time and take final screenshot
TASK_END_TIME=$(date +%s)
take_screenshot /tmp/task_final.png

# ==============================================================================
# Verify database state and gather results
# ==============================================================================
log "Gathering Sentrifugo state data..."

# 1. Check Department
DEPT_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_departments WHERE deptname='Veterans Assistance Program' AND isactive=1;" | tr -d '[:space:]')
if [ -z "$DEPT_EXISTS" ]; then DEPT_EXISTS="0"; fi

# 2. Check Job Titles
TITLE_VCM_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Veterans Case Manager' AND isactive=1;" | tr -d '[:space:]')
if [ -z "$TITLE_VCM_EXISTS" ]; then TITLE_VCM_EXISTS="0"; fi

TITLE_FOS_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Field Outreach Specialist' AND isactive=1;" | tr -d '[:space:]')
if [ -z "$TITLE_FOS_EXISTS" ]; then TITLE_FOS_EXISTS="0"; fi

# 3. Check Employee Reassignments (EMP004, EMP016, EMP011)
get_emp_data() {
    local EMPID=$1
    local DATA=$(sentrifugo_db_query "SELECT d.deptname, j.jobtitlename FROM main_users u LEFT JOIN main_departments d ON u.department_id = d.id LEFT JOIN main_jobtitles j ON u.jobtitle_id = j.id WHERE u.employeeId='${EMPID}';" 2>/dev/null | tr '\t' '|')
    echo "$DATA"
}

EMP004_DATA=$(get_emp_data "EMP004")
EMP016_DATA=$(get_emp_data "EMP016")
EMP011_DATA=$(get_emp_data "EMP011")

# Extract Dept and Title from piped string (e.g. "Veterans Assistance Program|Veterans Case Manager")
EMP004_DEPT=$(echo "$EMP004_DATA" | awk -F'|' '{print $1}')
EMP004_TITLE=$(echo "$EMP004_DATA" | awk -F'|' '{print $2}')

EMP016_DEPT=$(echo "$EMP016_DATA" | awk -F'|' '{print $1}')
EMP016_TITLE=$(echo "$EMP016_DATA" | awk -F'|' '{print $2}')

EMP011_DEPT=$(echo "$EMP011_DATA" | awk -F'|' '{print $1}')
EMP011_TITLE=$(echo "$EMP011_DATA" | awk -F'|' '{print $2}')

# 4. Check Leave Type
LEAVE_DAYS=$(sentrifugo_db_query "SELECT numberofdays FROM main_employeeleavetypes WHERE leavetype='Wellness & Respite Leave' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
if [ -z "$LEAVE_DAYS" ]; then LEAVE_DAYS="0"; fi

# 5. Check Holiday Group and Dates
HG_ID=$(sentrifugo_db_query "SELECT id FROM main_holidaygroups WHERE groupname='VAP Grant Holidays' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')

HOLIDAY_MEMORIAL="0"
HOLIDAY_VETERANS="0"
if [ -n "$HG_ID" ]; then
    GROUP_EXISTS="1"
    HOLIDAY_MEMORIAL=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_holidaydates WHERE groupid=${HG_ID} AND holidayname LIKE '%Memorial Day%' AND holidaydate='2026-05-25' AND isactive=1;" | tr -d '[:space:]')
    if [ -z "$HOLIDAY_MEMORIAL" ]; then HOLIDAY_MEMORIAL="0"; fi
    
    HOLIDAY_VETERANS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_holidaydates WHERE groupid=${HG_ID} AND holidayname LIKE '%Veterans Day%' AND holidaydate='2026-11-11' AND isactive=1;" | tr -d '[:space:]')
    if [ -z "$HOLIDAY_VETERANS" ]; then HOLIDAY_VETERANS="0"; fi
else
    GROUP_EXISTS="0"
fi

# ==============================================================================
# Write output to JSON for the Verifier
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_end": $TASK_END_TIME,
    "dept_created": $([ "$DEPT_EXISTS" -gt "0" ] && echo "true" || echo "false"),
    "title_vcm_created": $([ "$TITLE_VCM_EXISTS" -gt "0" ] && echo "true" || echo "false"),
    "title_fos_created": $([ "$TITLE_FOS_EXISTS" -gt "0" ] && echo "true" || echo "false"),
    "emp004_dept": "$EMP004_DEPT",
    "emp004_title": "$EMP004_TITLE",
    "emp016_dept": "$EMP016_DEPT",
    "emp016_title": "$EMP016_TITLE",
    "emp011_dept": "$EMP011_DEPT",
    "emp011_title": "$EMP011_TITLE",
    "leave_days": $LEAVE_DAYS,
    "group_exists": $([ "$GROUP_EXISTS" -eq "1" ] && echo "true" || echo "false"),
    "holiday_memorial": $([ "$HOLIDAY_MEMORIAL" -gt "0" ] && echo "true" || echo "false"),
    "holiday_veterans": $([ "$HOLIDAY_VETERANS" -gt "0" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Task results successfully exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="