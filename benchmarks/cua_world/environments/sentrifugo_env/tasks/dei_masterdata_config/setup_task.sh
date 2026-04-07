#!/bin/bash
echo "=== Setting up dei_masterdata_config task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ---- Clean up prior run artifacts ----
log "Cleaning up prior run artifacts..."

# Remove EMP021, EMP022 if they exist
for EMPID in EMP021 EMP022; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}';" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_users WHERE id=${UID_VAL};" 2>/dev/null || true
    fi
done

# Remove prefixes
for PFX in "Mx." "Prof." "Engr."; do
    sentrifugo_db_root_query "DELETE FROM main_prefix WHERE prefixname='${PFX}';" 2>/dev/null || true
done

# Remove ethnic codes
for EC in "MENA" "NHPI" "SEA" "MRAC"; do
    sentrifugo_db_root_query "DELETE FROM main_ethniccode WHERE ethniccode='${EC}';" 2>/dev/null || true
done

# Remove employment statuses
for STAT in "Seasonal Worker" "Fellowship"; do
    sentrifugo_db_root_query "DELETE FROM main_employmentstatustype WHERE statusname='${STAT}';" 2>/dev/null || true
done

# ---- Record Initial Counts for Anti-Gaming ----
PREFIX_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_prefix WHERE isactive=1;" | tr -d '[:space:]' || echo "0")
ETHNIC_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_ethniccode WHERE isactive=1;" | tr -d '[:space:]' || echo "0")
STATUS_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_employmentstatustype WHERE isactive=1;" | tr -d '[:space:]' || echo "0")
EMP_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_users WHERE isactive=1;" | tr -d '[:space:]' || echo "0")

echo "$PREFIX_COUNT" > /tmp/initial_prefix_count.txt
echo "$ETHNIC_COUNT" > /tmp/initial_ethnic_count.txt
echo "$STATUS_COUNT" > /tmp/initial_status_count.txt
echo "$EMP_COUNT" > /tmp/initial_emp_count.txt

log "Initial counts: Prefixes=$PREFIX_COUNT, EthnicCodes=$ETHNIC_COUNT, Statuses=$STATUS_COUNT, Employees=$EMP_COUNT"

# ---- Drop the manifest on the Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/dei_masterdata_update.txt << 'MANIFEST'
=============================================================
        DEI MASTER DATA UPDATE — EFFECTIVE IMMEDIATELY
        Approved by: Board DEI Committee, Jan 2026
=============================================================

SECTION 1: NEW NAME PREFIXES
-----------------------------
Add the following inclusive name prefixes to the HRMS:
  1. Mx.     (gender-neutral honorific)
  2. Prof.   (academic partnership staff)
  3. Engr.   (international engineering convention)


SECTION 2: NEW ETHNIC / DEMOGRAPHIC CODES
-------------------------------------------
Add the following demographic tracking categories:

  Code: MENA   | Name: Middle Eastern or North African
  Code: NHPI   | Name: Native Hawaiian or Pacific Islander
  Code: SEA    | Name: Southeast Asian
  Code: MRAC   | Name: Multiracial


SECTION 3: NEW EMPLOYMENT STATUS TYPES
----------------------------------------
Add the following employment arrangement types:
  1. Seasonal Worker
  2. Fellowship


SECTION 4: NEW EMPLOYEE ONBOARDING
------------------------------------
Onboard the following two staff members using the new
reference data created above:

Employee 1:
  Employee ID  : EMP021
  Prefix       : Mx.
  First Name   : Jordan
  Last Name    : Rivera
  Email        : jordan.rivera@sentrifugo.local
  Department   : Customer Support
  Job Title    : Customer Support Specialist
  Employment Status : Seasonal Worker
  Date of Joining   : 2026-01-15

Employee 2:
  Employee ID  : EMP022
  Prefix       : Engr.
  First Name   : Rajan
  Last Name    : Patel
  Email        : rajan.patel@sentrifugo.local
  Department   : Engineering
  Job Title    : Software Engineer
  Employment Status : Full Time
  Date of Joining   : 2026-01-20

=============================================================
NOTE: Do NOT remove or deactivate any existing reference data.
All existing prefixes, ethnic codes, and employment status
types must remain active.
=============================================================
MANIFEST

chown ga:ga /home/ga/Desktop/dei_masterdata_update.txt
log "DEI master data manifest created at ~/Desktop/dei_masterdata_update.txt"

# ---- Open Browser and Login ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 5

# Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

log "Task ready."
echo "=== Setup complete ==="