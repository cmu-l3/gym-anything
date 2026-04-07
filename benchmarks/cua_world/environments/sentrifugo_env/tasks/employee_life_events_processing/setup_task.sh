#!/bin/bash
echo "=== Setting up employee_life_events_processing task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_time

log "Injecting predictable starting state into the database..."

# Function to execute DB commands quickly
db_exec() {
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "$1" 2>/dev/null
}

db_query() {
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "$1" 2>/dev/null | tr -d '[:space:]'
}

# 1. EMP005 (Michael Davis)
UID_005=$(db_query "SELECT id FROM main_users WHERE employeeId='EMP005' LIMIT 1;")
if [ -n "$UID_005" ]; then
    db_exec "
    UPDATE main_users SET maritalstatus='Single' WHERE id=$UID_005;
    UPDATE main_employees_summary SET marital_status='Single' WHERE user_id=$UID_005;
    DELETE FROM main_employee_contactdetails WHERE user_id=$UID_005;
    INSERT INTO main_employee_contactdetails (user_id, presentaddress) VALUES ($UID_005, '123 Old Address St, Springfield, IL');
    DELETE FROM main_employee_emergencycontacts WHERE user_id=$UID_005;
    INSERT INTO main_employee_emergencycontacts (user_id, name, relationship, homephone) VALUES ($UID_005, 'Robert Davis', 'Brother', '555-0000');
    "
fi

# 2. EMP011 (Amanda Torres)
UID_011=$(db_query "SELECT id FROM main_users WHERE employeeId='EMP011' LIMIT 1;")
if [ -n "$UID_011" ]; then
    db_exec "
    UPDATE main_users SET lastname='Torres', emailaddress='amanda.torres@acmeglobe.com', maritalstatus='Single' WHERE id=$UID_011;
    UPDATE main_employees_summary SET marital_status='Single' WHERE user_id=$UID_011;
    "
fi

# 3. EMP014 (Sophia Brown)
UID_014=$(db_query "SELECT id FROM main_users WHERE employeeId='EMP014' LIMIT 1;")
if [ -n "$UID_014" ]; then
    db_exec "
    DELETE FROM main_employee_emergencycontacts WHERE user_id=$UID_014;
    INSERT INTO main_employee_emergencycontacts (user_id, name, relationship, homephone) VALUES ($UID_014, 'William Brown', 'Father', '555-1111');
    "
fi

# 4. EMP019 (Tyler Moore)
UID_019=$(db_query "SELECT id FROM main_users WHERE employeeId='EMP019' LIMIT 1;")
if [ -n "$UID_019" ]; then
    db_exec "
    DELETE FROM main_employee_contactdetails WHERE user_id=$UID_019;
    INSERT INTO main_employee_contactdetails (user_id, presentaddress, homephone) VALUES ($UID_019, '999 Old St, Columbus, OH', '555-9999');
    "
fi

log "Database starting state injected successfully."

# ---- Drop life events manifest on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/life_events_manifest.txt << 'MANIFEST'
ACME GLOBAL TECHNOLOGIES
HR Life Events Processing Manifest — End of Month
==================================================

Please process the following employee updates in the Sentrifugo HRMS immediately.
Navigate to the Employee module, search for each employee, and update ONLY the 
specified fields across the Personal Details, Contact Details, and Emergency Contacts tabs.

EVENT 1: MARRIAGE & RELOCATION
Employee: Michael Davis (EMP005)
Updates Required:
 - Marital Status: Update to "Married"
 - Present Address: Update to "742 Evergreen Terrace, Springfield, IL 62704"
 - Emergency Contacts: Add "Sarah Davis" (Relationship: Spouse, Home Phone: 555-0188)
   * DO NOT delete his existing emergency contact (Robert Davis).

EVENT 2: NAME CHANGE & MARRIAGE
Employee: Amanda Torres (EMP011)
Updates Required:
 - Last Name: Update to "Torres-Chen"
 - Marital Status: Update to "Married"
 - Work Email: Update to "amanda.torres-chen@company.com"

EVENT 3: EMERGENCY CONTACT UPDATE
Employee: Sophia Brown (EMP014)
Updates Required:
 - Emergency Contacts: Delete the existing contact "William Brown"
 - Emergency Contacts: Add a new contact "Emma Wilson" (Relationship: Sister, Home Phone: 555-0199)

EVENT 4: RELOCATION & PHONE CHANGE
Employee: Tyler Moore (EMP019)
Updates Required:
 - Present Address: Update to "1428 Elm Street, Columbus, OH 43215"
 - Home Phone: Update to "555-0210"

==================================================
Compliance Note: Ensure changes are saved on each respective tab before moving to the next.
MANIFEST

chown ga:ga /home/ga/Desktop/life_events_manifest.txt
log "Manifest created at ~/Desktop/life_events_manifest.txt"

# ---- Navigate to employee list ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start.png

log "Task ready."
echo "=== Setup complete ==="