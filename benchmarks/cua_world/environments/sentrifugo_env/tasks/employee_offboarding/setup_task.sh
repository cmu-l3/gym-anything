#!/bin/bash
echo "=== Setting up employee_offboarding task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

CURRENT_YEAR=$(date +%Y)

# ---- Clean up prior run artifacts ----
log "Cleaning up prior run artifacts..."
# Re-activate the 3 employees in case a prior run deactivated them
for EMPID in EMP013 EMP018 EMP020; do
    sentrifugo_db_root_query "UPDATE main_users SET isactive=1 WHERE employeeId='${EMPID}';" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET isactive=1 WHERE employeeId='${EMPID}';" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees SET isactive=1 WHERE user_id=(SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1);" 2>/dev/null || true
done
# Remove replacement hires if present from prior run
for EMPID in EMP021 EMP022; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_users WHERE id=${UID_VAL};" 2>/dev/null || true
        log "Removed prior-run employee ${EMPID}"
    fi
done
# Remove Austin Office Holidays group if present
HG_AUSTIN=$(sentrifugo_db_query "SELECT id FROM main_holidaygroups WHERE groupname='Austin Office Holidays' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$HG_AUSTIN" ]; then
    sentrifugo_db_root_query "DELETE FROM main_holidaydates WHERE groupid=${HG_AUSTIN};" 2>/dev/null || true
    sentrifugo_db_root_query "DELETE FROM main_holidaygroups WHERE id=${HG_AUSTIN};" 2>/dev/null || true
    log "Removed prior-run Austin Office Holidays group"
fi
log "Cleanup complete"

# ---- Drop offboarding manifest on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/hr_offboarding_manifest.txt << MANIFEST
ACME GLOBAL TECHNOLOGIES
HR Offboarding & Onboarding Manifest — Q1 2026
Issued by: Chief Human Resources Officer
================================================

This manifest contains three required actions. Complete ALL of them.

-----------------------------------------------------------------
ACTION 1: DEACTIVATE DEPARTING EMPLOYEES
-----------------------------------------------------------------
The following employees are leaving the company effective March 15, 2026.
Deactivate their accounts in Sentrifugo (do not delete — deactivate only).

  a. Daniel Wilson        (Employee ID: EMP013) — Voluntary resignation
  b. Nicole Anderson      (Employee ID: EMP018) — Voluntary resignation
  c. Lauren Jackson       (Employee ID: EMP020) — End of contract

-----------------------------------------------------------------
ACTION 2: ADD REPLACEMENT HIRES
-----------------------------------------------------------------
Add the following new employees to replace departing staff:

New Hire 1:
  Employee ID   : EMP021
  First Name    : Carlos
  Last Name     : Reyes
  Email         : carlos.reyes@acmeglobe.com
  Department    : Sales
  Job Title     : Sales Representative
  Date Joined   : 2026-03-16

New Hire 2:
  Employee ID   : EMP022
  First Name    : Mia
  Last Name     : Chen
  Email         : mia.chen@acmeglobe.com
  Department    : Marketing
  Job Title     : Marketing Specialist
  Date Joined   : 2026-03-16

-----------------------------------------------------------------
ACTION 3: CREATE REGIONAL HOLIDAY GROUP
-----------------------------------------------------------------
Create a new holiday group for the Austin, TX office with the following details:

  Group Name   : Austin Office Holidays
  Year         : ${CURRENT_YEAR}

  Add these two holidays to the group:

  Holiday 1:
    Name        : Texas Independence Day
    Date        : ${CURRENT_YEAR}-03-02
    Description : Texas state holiday — Republic of Texas declared independence

  Holiday 2:
    Name        : Juneteenth
    Date        : ${CURRENT_YEAR}-06-19
    Description : Federal holiday commemorating the end of slavery in the US

================================================
All three actions must be completed in Sentrifugo.
MANIFEST

chown ga:ga /home/ga/Desktop/hr_offboarding_manifest.txt
log "Offboarding manifest created at ~/Desktop/hr_offboarding_manifest.txt"

# ---- Navigate to employee list ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: offboarding manifest on Desktop, 3 employees active, 0 replacement hires, no Austin holidays group"
echo "=== employee_offboarding task setup complete ==="
