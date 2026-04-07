#!/bin/bash
echo "=== Setting up corporate_divestiture_segregation task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

log "Cleaning up prior run artifacts..."

# Remove Job Title if exists
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename='Divestiture Transition Staff';" 2>/dev/null || true

# Remove Employment Status if exists (try standard tables)
sentrifugo_db_root_query "DELETE FROM main_employmentstatus WHERE statusname='Divested Entity' OR statusname='Divested Entity';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_employeestatus WHERE statusname='Divested Entity' OR employeestatus='Divested Entity';" 2>/dev/null || true

# Restore original emails and reset job titles for the target employees 
# to ensure idempotency. Original seeded emails are generally sentrifugo.local
for EMPID in EMP008 EMP010 EMP012 EMP015 EMP018 EMP020; do
    EMAIL=$(sentrifugo_db_query "SELECT emailaddress FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;")
    if [ -n "$EMAIL" ] && [ "$EMAIL" != "NULL" ]; then
        PREFIX=$(echo "$EMAIL" | awk -F'@' '{print $1}')
        if [ -n "$PREFIX" ] && [ "$PREFIX" != "NULL" ]; then
            sentrifugo_db_root_query "UPDATE main_users SET emailaddress='${PREFIX}@sentrifugo.local' WHERE employeeId='${EMPID}';" 2>/dev/null || true
        fi
    fi
done

# ---- Drop memo on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/divestiture_memo.txt << 'MEMO'
CONFIDENTIAL: CORPORATE DIVESTITURE MEMO
To: HR Administration
From: VP of Human Resources
Date: Q1 2026

Subject: Spin-off of QA & Customer Support to "QA-Serve"

As part of the upcoming divestiture, we are separating our Quality Assurance and Customer Support teams into a standalone entity named "QA-Serve".

Before IT begins the active directory migration, HR must isolate the affected employees in our Sentrifugo HRMS immediately.

ACTION ITEMS:

1. Create a new Job Title:
   Name: Divestiture Transition Staff
   Description: Temporary designation for employees moving to the new QA-Serve entity.

2. Create a new Employment Status:
   Name: Divested Entity
   Description: Separated from parent company via spin-off.

3. Update the following 6 employees to reflect their transition:
   - EMP008
   - EMP010
   - EMP012
   - EMP015
   - EMP018
   - EMP020

   For EACH of these employees, edit their profile and:
   a) Change their Job Title to "Divestiture Transition Staff"
   b) Change their Employment Status to "Divested Entity"
   c) Update their email address domain to "@qaserve.com"
      (IMPORTANT: You must preserve their existing first.last prefix!
       For example, amanda.white@sentrifugo.local must become amanda.white@qaserve.com)

Do not modify any other employees in the system.
MEMO

chown ga:ga /home/ga/Desktop/divestiture_memo.txt
log "Divestiture memo created at ~/Desktop/divestiture_memo.txt"

# ---- Navigate to employee list ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="