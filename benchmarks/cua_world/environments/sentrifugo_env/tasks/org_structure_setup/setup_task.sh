#!/bin/bash
echo "=== Setting up org_structure_setup task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# ---- Clean up any prior run artifacts ----
log "Cleaning up prior run artifacts for org_structure_setup..."
# Remove EMP021, EMP022, EMP023 if present
for EMPID in EMP021 EMP022 EMP023; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_users WHERE id=${UID_VAL};" 2>/dev/null || true
        log "Removed employee ${EMPID}"
    fi
done
# Remove Product Management department if present
sentrifugo_db_root_query "UPDATE main_departments SET isactive=0 WHERE deptcode='PM';" 2>/dev/null || true
# Remove product job titles if present
for JTC in VP-PROD SR-PM PM-JR; do
    sentrifugo_db_root_query "UPDATE main_jobtitles SET isactive=0 WHERE jobtitlecode='${JTC}';" 2>/dev/null || true
done

# ---- Drop department charter on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/department_charter.txt << 'CHARTER'
ACME GLOBAL TECHNOLOGIES
New Department Charter — Approved by CEO
=========================================

DEPARTMENT DETAILS
------------------
Department Name : Product Management
Department Code : PM
Business Unit   : Technology Services
Description     : Responsible for product strategy, roadmap definition, and cross-functional
                  alignment between engineering, design, and business stakeholders.
Start Date      : 2026-01-01

JOB TITLES TO CREATE FOR THIS DEPARTMENT
-----------------------------------------
1. Title Name : VP of Product
   Title Code : VP-PROD
   Description: Senior leadership role overseeing the entire product portfolio

2. Title Name : Senior Product Manager
   Title Code : SR-PM
   Description: Leads product initiatives for a major product line

3. Title Name : Product Manager
   Title Code : PM-JR
   Description: Manages product features and coordinates delivery

INITIAL STAFF — ADD THESE EMPLOYEES
-------------------------------------
Employee 1:
  Employee ID   : EMP021
  First Name    : Marcus
  Last Name     : Webb
  Email         : marcus.webb@acmeglobe.com
  Job Title     : VP of Product
  Department    : Product Management
  Date Joined   : 2026-01-15

Employee 2:
  Employee ID   : EMP022
  First Name    : Priya
  Last Name     : Sharma
  Email         : priya.sharma@acmeglobe.com
  Job Title     : Senior Product Manager
  Department    : Product Management
  Date Joined   : 2026-01-15

Employee 3:
  Employee ID   : EMP023
  First Name    : Lucas
  Last Name     : Fernandez
  Email         : lucas.fernandez@acmeglobe.com
  Job Title     : Product Manager
  Department    : Product Management
  Date Joined   : 2026-02-01

NOTE: All three employees should be assigned the Employee role.
=========================================
CHARTER

chown ga:ga /home/ga/Desktop/department_charter.txt
log "Department charter created at ~/Desktop/department_charter.txt"

# ---- Navigate to Departments page ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/departments"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: department charter on Desktop, no Product Management dept exists yet"
echo "=== org_structure_setup task setup complete ==="
