#!/bin/bash
echo "=== Setting up training_cohort_onboarding task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

log "Cleaning up any prior run artifacts..."

# 1. Remove the "Training Coordinator" job title if it exists
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename='Training Coordinator';" 2>/dev/null || true

# 2. Remove EMP021, EMP022, EMP023 if they exist
for EMPID in EMP021 EMP022 EMP023; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM main_managers WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_users WHERE id=${UID_VAL};" 2>/dev/null || true
        log "Removed employee ${EMPID}"
    fi
done

# 3. Create the onboarding packet on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/training_cohort_packet.txt << 'PACKET'
═══════════════════════════════════════════════════════
       NEW HIRE ONBOARDING PACKET — Q1 2026 COHORT
       Prepared by: VP of Human Resources
       Date: 2026-01-27
═══════════════════════════════════════════════════════

INSTRUCTIONS:
Before adding employees, create the new job title listed
below. Then add each employee with ALL fields specified.
All three employees share a start date of February 3, 2026.

───────────────────────────────────────────────────────
NEW JOB TITLE TO CREATE:
  Title Name: Training Coordinator
───────────────────────────────────────────────────────

EMPLOYEE 1:
  Employee ID:       EMP021
  First Name:        Amara
  Last Name:         Okafor
  Email:             amara.okafor@company.com
  Date of Birth:     1992-06-15
  Gender:            Female
  Date of Joining:   2026-02-03
  Department:        Human Resources
  Job Title:         Training Coordinator
  Reporting Manager: Sarah Thompson (EMP005)
  Employment Status: Active
  Role:              employee

EMPLOYEE 2:
  Employee ID:       EMP022
  First Name:        Rajesh
  Last Name:         Venkataraman
  Email:             rajesh.venkataraman@company.com
  Date of Birth:     1988-11-22
  Gender:            Male
  Date of Joining:   2026-02-03
  Department:        Engineering
  Job Title:         Software Engineer
  Reporting Manager: James Anderson (EMP001)
  Employment Status: Active
  Role:              employee

EMPLOYEE 3:
  Employee ID:       EMP023
  First Name:        Sofia
  Last Name:         Andersson
  Email:             sofia.andersson@company.com
  Date of Birth:     1995-03-08
  Gender:            Female
  Date of Joining:   2026-02-03
  Department:        Sales
  Job Title:         Sales Representative
  Reporting Manager: Robert Kim (EMP010)
  Employment Status: Active
  Role:              employee

───────────────────────────────────────────────────────
VERIFICATION: After entry, confirm all 3 employees
appear in the active employee list with correct
departments and job titles.
═══════════════════════════════════════════════════════
PACKET

chown ga:ga /home/ga/Desktop/training_cohort_packet.txt
log "Onboarding packet created at ~/Desktop/training_cohort_packet.txt"

# 4. Navigate to Employee listing page
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task setup complete"
echo "=== Setup complete ==="