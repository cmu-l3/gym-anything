#!/bin/bash
echo "=== Setting up service_desk_ticket_resolution task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# Try to insert Service Desk Departments and Categories to ensure module works
sentrifugo_db_root_query "INSERT IGNORE INTO main_servicedepartments (deptname, isactive) VALUES ('IT Support', 1), ('Facilities Management', 1), ('Human Resources', 1);" 2>/dev/null || true
sentrifugo_db_root_query "INSERT IGNORE INTO main_servicecategories (categoryname, department_id, isactive) VALUES ('Network', 1, 1), ('Hardware', 1, 1), ('HVAC', 2, 1), ('Payroll', 3, 1), ('Ergonomics', 3, 1);" 2>/dev/null || true

# Try to populate tickets
# We will use simple insert; if it fails due to schema differences, the instructions tell the agent to create them.
# Get some user IDs
UID_SARAH=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Sarah' AND lastname='Johnson' LIMIT 1;" | tr -d '[:space:]')
UID_ROBERT=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Robert' AND lastname='Taylor' LIMIT 1;" | tr -d '[:space:]')
UID_EMILY=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Emily' AND lastname='Williams' LIMIT 1;" | tr -d '[:space:]')
UID_MICHAEL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Michael' AND lastname='Chen' LIMIT 1;" | tr -d '[:space:]')
UID_DAVID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='David' AND lastname='Miller' LIMIT 1;" | tr -d '[:space:]')

# Default user ID if specific ones not found
[ -z "$UID_SARAH" ] && UID_SARAH=2
[ -z "$UID_ROBERT" ] && UID_ROBERT=3
[ -z "$UID_EMILY" ] && UID_EMILY=4
[ -z "$UID_MICHAEL" ] && UID_MICHAEL=5
[ -z "$UID_DAVID" ] && UID_DAVID=6

# Attempt to insert into main_servicerequests
DATE_STR=$(date '+%Y-%m-%d %H:%M:%S')
for TBL in main_servicerequests main_service_requests; do
    sentrifugo_db_root_query "INSERT INTO $TBL (requestcode, user_id, subject, description, status, created_date, isactive) VALUES 
    ('SR-1001', $UID_SARAH, 'VPN access failing remotely', 'Cannot connect to VPN from home office.', 'Open', '$DATE_STR', 1),
    ('SR-1002', $UID_ROBERT, 'Need a new secondary monitor', 'My second monitor is flickering and needs replacement.', 'Open', '$DATE_STR', 1),
    ('SR-1003', $UID_EMILY, 'AC in zone B is too cold', 'The temperature in Zone B is freezing, please adjust.', 'Open', '$DATE_STR', 1),
    ('SR-1004', $UID_MICHAEL, 'Payroll tax deduction question', 'My state tax deduction looks incorrect this month.', 'Open', '$DATE_STR', 1),
    ('SR-1005', $UID_DAVID, 'Request for ergonomic standing desk', 'Need a standing desk for back issues.', 'Open', '$DATE_STR', 1);" 2>/dev/null && break
done

# Drop the log on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/weekend_maintenance_log.txt << 'LOG_DOC'
WEEKEND MAINTENANCE RESOLUTION LOG
Shift: Saturday-Sunday, Q1 2026
Prepared by: Facilities & IT Field Team

The following employee requests have been physically resolved and need to be closed in the system.
If you cannot find the tickets in the Service Desk module (e.g. due to system outage), you MUST create them first before closing them.

1. Employee: Sarah Johnson
   Issue: VPN access failing remotely
   Resolution to enter: "Reset user AD password, synced RSA token, and verified successful test login from external IP."
   Action: CLOSE TICKET

2. Employee: Robert Taylor
   Issue: Need a new secondary monitor
   Resolution to enter: "Deployed 27-inch Dell U2720Q to desk 4B. Connected via DisplayPort and configured extended desktop."
   Action: CLOSE TICKET

3. Employee: Emily Williams
   Issue: AC in zone B is too cold
   Resolution to enter: "HVAC tech inspected Zone B damper. Replaced faulty actuator and recalibrated thermostat to 72F baseline."
   Action: CLOSE TICKET

--------------------------------------------------
NOTE: The following issues are pending parts/approvals. DO NOT close these tickets. They must remain Open/New:
- Michael Chen: "Payroll tax deduction question" (Awaiting Finance)
- David Miller: "Request for ergonomic standing desk" (Awaiting Medical Note)
LOG_DOC

chown ga:ga /home/ga/Desktop/weekend_maintenance_log.txt

# Navigate to Service Desk
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/servicedesk"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="