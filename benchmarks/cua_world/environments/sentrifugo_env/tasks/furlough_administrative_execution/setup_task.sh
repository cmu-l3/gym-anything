#!/bin/bash
echo "=== Setting up furlough_administrative_execution task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo HTTP to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

log "Cleaning up any prior run artifacts..."

# 1. Re-activate Annual Leave if it was deactivated
sentrifugo_db_root_query "UPDATE main_employeeleavetypes SET isactive=1 WHERE leavetype='Annual Leave';" 2>/dev/null || true

# 2. Reset employees and delete the "Furloughed - Unpaid" status if it exists
FURLOUGH_ID=$(sentrifugo_db_query "SELECT id FROM main_employmentstatus WHERE statusname='Furloughed - Unpaid';" | tr -d '[:space:]')
if [ -n "$FURLOUGH_ID" ]; then
    # Reset any affected users to default Full Time (id=1 usually, or just remove from Furloughed)
    sentrifugo_db_root_query "UPDATE main_users SET employment_status_id=1 WHERE employment_status_id=${FURLOUGH_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees SET employment_status_id=1 WHERE employment_status_id=${FURLOUGH_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET employment_status_id=1 WHERE employment_status_id=${FURLOUGH_ID};" 2>/dev/null || true
    # Delete the status
    sentrifugo_db_root_query "DELETE FROM main_employmentstatus WHERE id=${FURLOUGH_ID};" 2>/dev/null || true
    log "Removed prior-run Furloughed status and reset employees."
fi

# 3. Delete the announcement if it exists
sentrifugo_db_root_query "DELETE FROM main_announcements WHERE title='Plant Operations Pause';" 2>/dev/null || true

# 4. Generate the Furlough Directive on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/furlough_directive.txt << 'DIRECTIVE'
MEMORANDUM: IMMEDIATE ACTION REQUIRED
To: HR Administration
From: Plant Director
Subject: Production Staff Furlough Execution

Due to the severe Q1 biomass fuel shortage, production operations are temporarily paused. Execute the following HRMS updates immediately:

1. STATUS CREATION:
   Navigate to the Employment Status configuration and create a new status called exactly: 
   "Furloughed - Unpaid"

2. EMPLOYEE RECLASSIFICATION:
   Update the employment status for the following Production staff to the new "Furloughed - Unpaid" status:
   - EMP008 (Michael Taylor)
   - EMP011 (James Thomas)
   - EMP014 (William White)
   - EMP017 (Ethan Martin)

3. PTO FREEZE:
   To prevent PTO usage or payouts during the furlough, navigate to Leave Types and deactivate the "Annual Leave" policy.

4. STAFF NOTIFICATION:
   Create an active Announcement with the title exactly: "Plant Operations Pause"
   Description: "Due to supply chain constraints, production operations are paused until further notice."
   Set the dates to cover the current month.
DIRECTIVE

chown ga:ga /home/ga/Desktop/furlough_directive.txt
log "Directive created at ~/Desktop/furlough_directive.txt"

# Log into Sentrifugo and leave the browser at the dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_initial.png

log "Task ready."
echo "=== Setup complete ==="