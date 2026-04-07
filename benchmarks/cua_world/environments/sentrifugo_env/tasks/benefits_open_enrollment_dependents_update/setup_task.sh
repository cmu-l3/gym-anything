#!/bin/bash
echo "=== Setting up benefits_open_enrollment_dependents_update task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# ---- Clean up prior run artifacts ----
log "Cleaning up prior dependent records..."
# Dynamically find the dependents table (usually main_employeedependents)
TABLE_NAME=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SHOW TABLES LIKE '%dependent%';" | head -1 | tr -d '[:space:]')

if [ -n "$TABLE_NAME" ]; then
    log "Found dependents table: $TABLE_NAME"
    # Delete any existing dependents for the target employees to ensure a clean slate
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
        DELETE d FROM ${TABLE_NAME} d 
        JOIN main_users u ON d.user_id = u.id 
        WHERE u.employeeId IN ('EMP001', 'EMP002', 'EMP007', 'EMP019');
    " 2>/dev/null || true
else
    log "WARNING: Could not find dependents table for cleanup."
fi

# ---- Drop enrollment memo on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/open_enrollment_2026.txt << 'MEMO'
ACME GLOBAL TECHNOLOGIES
2026 Benefits Open Enrollment - Dependent Additions
===================================================

Please process the following dependent additions for the new health insurance plan year.
Add these to the respective employees' profiles in the HRMS. If a specific relationship
type (like Domestic Partner) is not available in the dropdown, choose the closest equivalent
(such as Partner or Other).

1. Employee: Sarah Mitchell (EMP002)
   Dependent Name: John Mitchell
   Relationship: Spouse
   Date of Birth: 1985-04-12

2. Employee: Robert Taylor (EMP007)
   Dependent Name: Emma Taylor
   Relationship: Child
   Date of Birth: 2020-08-30

   Dependent Name: Noah Taylor
   Relationship: Child
   Date of Birth: 2022-11-15

3. Employee: Tyler Moore (EMP019)
   Dependent Name: Alex Rivera
   Relationship: Domestic Partner
   Date of Birth: 1990-02-28

4. Employee: James Anderson (EMP001)
   Dependent Name: Buster Anderson
   Relationship: Pet
   Date of Birth: 2018-05-10
   
   *** HR DIRECTOR NOTE *** 
   Do NOT enter record #4 into the system. Buster is a dog. 
   Pets are not eligible for the corporate health plan. Skip this entirely!
   ************************
MEMO

chown ga:ga /home/ga/Desktop/open_enrollment_2026.txt
log "Open enrollment memo created at ~/Desktop/open_enrollment_2026.txt"

# ---- Navigate to employee list ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: memo placed on Desktop, DB cleaned, UI ready on Employee list."
echo "=== Setup complete ==="