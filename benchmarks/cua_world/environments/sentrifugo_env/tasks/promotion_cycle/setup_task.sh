#!/bin/bash
echo "=== Setting up promotion_cycle task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# ---- Remove Engineering Manager job title if it exists from a prior run ----
sentrifugo_db_root_query "UPDATE main_jobtitles SET isactive=0 WHERE jobtitlecode='ENG-MGR';" 2>/dev/null || true
log "Cleaned up ENG-MGR job title from any prior run"

# ---- Ensure all 4 promotion targets have their pre-promotion titles ----
# James Anderson (EMP001): currently Senior Software Engineer → will be promoted to Engineering Manager
JT_SWE_SR=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='SWE-SR' LIMIT 1;" | tr -d '[:space:]')
# Jessica Liu (EMP006): currently Software Engineer → will be promoted to Senior Software Engineer
JT_SWE_JR=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='SWE-JR' LIMIT 1;" | tr -d '[:space:]')
# Jennifer Martinez (EMP012): currently Data Analyst → will be promoted to Senior Data Scientist
JT_DS_JR=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='DS-JR' LIMIT 1;" | tr -d '[:space:]')
# Tyler Moore (EMP019): currently Sales Representative → will be promoted to Sales Manager
JT_SALES_REP=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlecode='SALES-REP' LIMIT 1;" | tr -d '[:space:]')

EMP001_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP001' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP006_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP006' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP012_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP012' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP019_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP019' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')

# Reset to pre-promotion titles (in case prior run left them in promoted state)
if [ -n "$EMP001_UID" ] && [ -n "$JT_SWE_SR" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET jobtitle_id=${JT_SWE_SR} WHERE id=${EMP001_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET jobtitle_id=${JT_SWE_SR}, jobtitle_name='Senior Software Engineer' WHERE user_id=${EMP001_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees SET jobtitle_id=${JT_SWE_SR} WHERE user_id=${EMP001_UID};" 2>/dev/null || true
fi
if [ -n "$EMP006_UID" ] && [ -n "$JT_SWE_JR" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET jobtitle_id=${JT_SWE_JR} WHERE id=${EMP006_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET jobtitle_id=${JT_SWE_JR}, jobtitle_name='Software Engineer' WHERE user_id=${EMP006_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees SET jobtitle_id=${JT_SWE_JR} WHERE user_id=${EMP006_UID};" 2>/dev/null || true
fi
if [ -n "$EMP012_UID" ] && [ -n "$JT_DS_JR" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET jobtitle_id=${JT_DS_JR} WHERE id=${EMP012_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET jobtitle_id=${JT_DS_JR}, jobtitle_name='Data Analyst' WHERE user_id=${EMP012_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees SET jobtitle_id=${JT_DS_JR} WHERE user_id=${EMP012_UID};" 2>/dev/null || true
fi
if [ -n "$EMP019_UID" ] && [ -n "$JT_SALES_REP" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET jobtitle_id=${JT_SALES_REP} WHERE id=${EMP019_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET jobtitle_id=${JT_SALES_REP}, jobtitle_name='Sales Representative' WHERE user_id=${EMP019_UID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees SET jobtitle_id=${JT_SALES_REP} WHERE user_id=${EMP019_UID};" 2>/dev/null || true
fi
log "Pre-promotion titles confirmed for all 4 employees"

# ---- Drop promotions document on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/q1_2026_promotions.txt << 'PROMOS'
ACME GLOBAL TECHNOLOGIES
Q1 2026 Promotion Cycle — Final Decisions
Approved by: VP of Human Resources
=========================================

The following promotions are effective March 1, 2026.
Update each employee's job title in the HRMS immediately.

PROMOTION DECISIONS
-------------------

1. Employee     : James Anderson (EMP001)
   Current Title: Senior Software Engineer
   New Title    : Engineering Manager
   Title Code   : ENG-MGR
   NOTE: This is a NEW job title — create it in the system before assigning.
   Description  : Manages a team of software engineers; bridge between IC and leadership

2. Employee     : Jessica Liu (EMP006)
   Current Title: Software Engineer
   New Title    : Senior Software Engineer
   Title Code   : SWE-SR

3. Employee     : Jennifer Martinez (EMP012)
   Current Title: Data Analyst
   New Title    : Senior Data Scientist
   Title Code   : DS-SR

4. Employee     : Tyler Moore (EMP019)
   Current Title: Sales Representative
   New Title    : Sales Manager
   Title Code   : SALES-MGR

ACTION REQUIRED:
- Create the Engineering Manager job title (ENG-MGR) if it does not exist
- Update all four employees to their new job titles as listed above
=========================================
PROMOS

chown ga:ga /home/ga/Desktop/q1_2026_promotions.txt
log "Promotions document created at ~/Desktop/q1_2026_promotions.txt"

# ---- Navigate to Job Titles page ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/jobtitles"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: promotion document on Desktop, Engineering Manager title does not yet exist"
echo "=== promotion_cycle task setup complete ==="
