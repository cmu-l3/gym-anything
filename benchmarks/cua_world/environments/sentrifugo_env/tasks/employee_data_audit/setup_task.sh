#!/bin/bash
echo "=== Setting up employee_data_audit task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# ---- Get department IDs ----
DEPT_SWE=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptcode='SWE' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
DEPT_DS=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptcode='DS' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
DEPT_DEVOPS=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptcode='DEVOPS' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
DEPT_FIN=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptcode='FIN' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
DEPT_SALES=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptcode='SALES' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
log "Dept IDs: SWE=$DEPT_SWE DS=$DEPT_DS DEVOPS=$DEPT_DEVOPS FIN=$DEPT_FIN SALES=$DEPT_SALES"

# ---- Get job title IDs for injected wrong values ----
JT_SWE_JR=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='SWE-JR' LIMIT 1;" | tr -d '[:space:]')
JT_SALES_REP=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='SALES-REP' LIMIT 1;" | tr -d '[:space:]')
JT_DEVOPS_JR=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='DEVOPS-JR' LIMIT 1;" | tr -d '[:space:]')
JT_FIN_ANL=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='FIN-ANL' LIMIT 1;" | tr -d '[:space:]')
log "JT IDs: SWE-JR=$JT_SWE_JR SALES-REP=$JT_SALES_REP DEVOPS-JR=$JT_DEVOPS_JR FIN-ANL=$JT_FIN_ANL"

# ---- Get employee user IDs ----
EMP003_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP003' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP007_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP007' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP011_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP011' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP015_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP015' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
log "Employee UIDs: EMP003=$EMP003_UID EMP007=$EMP007_UID EMP011=$EMP011_UID EMP015=$EMP015_UID"

# ---- Inject errors ----
# EMP003 David Nguyen: correct=Finance Manager/Finance & Accounting → inject=Software Engineer/Software Engineering
sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_SWE}, jobtitle_id=${JT_SWE_JR} WHERE id=${EMP003_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_SWE}, department_name='Software Engineering', jobtitle_id=${JT_SWE_JR}, jobtitle_name='Software Engineer' WHERE user_id=${EMP003_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees SET department_id=${DEPT_SWE}, jobtitle_id=${JT_SWE_JR} WHERE user_id=${EMP003_UID};" 2>/dev/null || true

# EMP007 Robert Patel: correct=Senior Data Scientist/Data Science → inject=Sales Representative/Sales
sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_SALES}, jobtitle_id=${JT_SALES_REP} WHERE id=${EMP007_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_SALES}, department_name='Sales', jobtitle_id=${JT_SALES_REP}, jobtitle_name='Sales Representative' WHERE user_id=${EMP007_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees SET department_id=${DEPT_SALES}, jobtitle_id=${JT_SALES_REP} WHERE user_id=${EMP007_UID};" 2>/dev/null || true

# EMP011 Matthew Garcia: correct=Marketing Specialist/Marketing → inject=Systems Engineer/DevOps & Infrastructure
sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_DEVOPS}, jobtitle_id=${JT_DEVOPS_JR} WHERE id=${EMP011_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_DEVOPS}, department_name='DevOps & Infrastructure', jobtitle_id=${JT_DEVOPS_JR}, jobtitle_name='Systems Engineer' WHERE user_id=${EMP011_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees SET department_id=${DEPT_DEVOPS}, jobtitle_id=${JT_DEVOPS_JR} WHERE user_id=${EMP011_UID};" 2>/dev/null || true

# EMP015 Kevin Hernandez: correct=Systems Engineer/DevOps & Infrastructure → inject=Financial Analyst/Finance & Accounting
sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_FIN}, jobtitle_id=${JT_FIN_ANL} WHERE id=${EMP015_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_FIN}, department_name='Finance & Accounting', jobtitle_id=${JT_FIN_ANL}, jobtitle_name='Financial Analyst' WHERE user_id=${EMP015_UID};" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employees SET department_id=${DEPT_FIN}, jobtitle_id=${JT_FIN_ANL} WHERE user_id=${EMP015_UID};" 2>/dev/null || true

# ---- Drop reference roster file on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/hr_verified_roster.txt << 'ROSTER'
ACME GLOBAL TECHNOLOGIES
Verified Employee Directory — HR Audit Reference
Generated by HR Compliance Team — Confidential
=================================================
Format: Employee ID | Full Name | Job Title | Department
-------------------------------------------------
EMP001 | James Anderson       | Senior Software Engineer    | Software Engineering
EMP002 | Sarah Mitchell       | HR Manager                  | Human Resources
EMP003 | David Nguyen         | Finance Manager             | Finance & Accounting
EMP004 | Emily Rodriguez      | Marketing Manager           | Marketing
EMP005 | Michael Thompson     | Sales Manager               | Sales
EMP006 | Jessica Liu          | Software Engineer           | Software Engineering
EMP007 | Robert Patel         | Senior Data Scientist       | Data Science
EMP008 | Ashley Johnson       | HR Specialist               | Human Resources
EMP009 | Christopher Williams | DevOps Lead                 | DevOps & Infrastructure
EMP010 | Amanda Davis         | Financial Analyst           | Finance & Accounting
EMP011 | Matthew Garcia       | Marketing Specialist        | Marketing
EMP012 | Jennifer Martinez    | Data Analyst                | Data Science
EMP013 | Daniel Wilson        | Sales Representative        | Sales
EMP014 | Stephanie Brown      | Customer Success Manager    | Customer Success
EMP015 | Kevin Hernandez      | Systems Engineer            | DevOps & Infrastructure
EMP016 | Rachel Lee           | Software Engineer           | Software Engineering
EMP017 | Brian Taylor         | Financial Analyst           | Finance & Accounting
EMP018 | Nicole Anderson      | Marketing Specialist        | Marketing
EMP019 | Tyler Moore          | Sales Representative        | Sales
EMP020 | Lauren Jackson       | Customer Support Specialist | Customer Success
-------------------------------------------------
ACTION REQUIRED: Update any HRMS records that do not match this roster.
ROSTER

chown ga:ga /home/ga/Desktop/hr_verified_roster.txt
log "Reference roster file created at ~/Desktop/hr_verified_roster.txt"

# ---- Navigate to employee list ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: employee list visible, 4 records contain incorrect dept/job title"
echo "=== employee_data_audit task setup complete ==="
