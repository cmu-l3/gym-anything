#!/bin/bash
echo "=== Setting up grant_funded_program_initialization task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time (for anti-gaming and logs)
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Clean up any prior run artifacts to ensure a pristine state
# ==============================================================================
log "Cleaning up prior run artifacts..."

# Delete department if it exists
sentrifugo_db_root_query "DELETE FROM main_departments WHERE deptname='Veterans Assistance Program';" 2>/dev/null || true

# Delete job titles if they exist
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename IN ('Veterans Case Manager', 'Field Outreach Specialist');" 2>/dev/null || true

# Delete leave type if it exists
sentrifugo_db_root_query "DELETE FROM main_employeeleavetypes WHERE leavetype='Wellness & Respite Leave';" 2>/dev/null || true

# Delete holiday group and its dates if they exist
HG_ID=$(sentrifugo_db_query "SELECT id FROM main_holidaygroups WHERE groupname='VAP Grant Holidays' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$HG_ID" ]; then
    sentrifugo_db_root_query "DELETE FROM main_holidaydates WHERE groupid=${HG_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "DELETE FROM main_holidaygroups WHERE id=${HG_ID};" 2>/dev/null || true
fi

# ==============================================================================
# 2. Reset target employees to known defaults (to ensure task starts cleanly)
# ==============================================================================
log "Resetting employees EMP004, EMP016, EMP011 to default departments/titles..."

DEFAULT_DEPT=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE isactive=1 LIMIT 1;" | tr -d '[:space:]')
DEFAULT_TITLE=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE isactive=1 LIMIT 1;" | tr -d '[:space:]')

for EMPID in EMP004 EMP016 EMP011; do
    UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID" ] && [ -n "$DEFAULT_DEPT" ] && [ -n "$DEFAULT_TITLE" ]; then
        sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEFAULT_DEPT}, jobtitle_id=${DEFAULT_TITLE} WHERE id=${UID};" 2>/dev/null || true
        sentrifugo_db_root_query "UPDATE main_employees SET department_id=${DEFAULT_DEPT}, jobtitle_id=${DEFAULT_TITLE} WHERE user_id=${UID};" 2>/dev/null || true
        sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEFAULT_DEPT}, jobtitle_id=${DEFAULT_TITLE} WHERE user_id=${UID};" 2>/dev/null || true
    fi
done

# ==============================================================================
# 3. Create the configuration memo
# ==============================================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/grant_initialization_memo.txt << 'EOF'
COMMUNITY HEALTH SERVICES INC.
Memorandum: Veterans Assistance Program Initialization
Date: March 11, 2026
======================================================

We have successfully secured federal funding for the new "Veterans Assistance Program". 
Please configure the HRMS immediately with the following settings so we can begin operations.

1. ORGANIZATION SETUP
---------------------
- New Department Name: Veterans Assistance Program
- Department Code: VAP
- New Job Titles to Create: 
    * "Veterans Case Manager"
    * "Field Outreach Specialist"

2. STAFFING REASSIGNMENTS
-------------------------
The following existing staff members are moving to this new program. 
Please update their Employee records (Department and Job Title):
- EMP004 (Michael Johnson) -> Veterans Case Manager
- EMP016 (Matthew Taylor) -> Field Outreach Specialist
- EMP011 (David Moore) -> Field Outreach Specialist

3. LEAVE AND WELLNESS CONFIGURATION
-----------------------------------
Due to the nature of this work, the grant funds a specific trauma/wellness leave.
- New Leave Type: "Wellness & Respite Leave"
- Leave Code: WRL
- Days Allocated: 5

4. HOLIDAY OBSERVANCES
----------------------
This federal grant requires us to observe specific holidays for this department.
- New Holiday Group: "VAP Grant Holidays"
- Add these holidays to the group for the year 2026:
    * Memorial Day: May 25, 2026
    * Veterans Day: November 11, 2026

Please ensure all components are active in the system.
EOF
chown ga:ga /home/ga/Desktop/grant_initialization_memo.txt
log "Grant initialization memo created."

# ==============================================================================
# 4. Final UI Setup
# ==============================================================================
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_initial_state.png

log "=== Task setup complete ==="