#!/bin/bash
echo "=== Setting up post_probation_leave_allocation task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_time.txt

log "Preparing leave types..."
# Ensure Annual Leave and Sick Leave are active
sentrifugo_db_root_query "UPDATE main_employeeleavetypes SET isactive=1 WHERE leavetype IN ('Annual Leave', 'Sick Leave');" 2>/dev/null || true

log "Preparing users and clearing old allocations..."
# Reactivate the users if they were deactivated by another task
sentrifugo_db_root_query "UPDATE main_users SET isactive=1 WHERE employeeId IN ('EMP012', 'EMP013', 'EMP017', 'EMP019');" 2>/dev/null || true

# Delete existing 2026 allocations for these users to ensure clean slate
for EMPID in EMP012 EMP013 EMP017 EMP019; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM main_employeeleaveallocations WHERE user_id=${UID_VAL} AND year='2026';" 2>/dev/null || true
    fi
done

log "Creating allocation memo..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/leave_allocation_memo.txt << 'EOF'
MEMORANDUM
TO: HR Administration
FROM: First-Line Supervisor, Admin Support
DATE: March 11, 2026
SUBJECT: Post-Probation Leave Allocations (FY 2026)

The following employees have reached their 90-day milestone.
Please update their Leave Allocations in Sentrifugo for the year 2026.

IMPORTANT DATA ENTRY RULE:
The HRMS requires allocations to be entered in DAYS, but payroll tracks in hours.
You must convert the hours below into days before entry.
Assume a standard 8-hour workday (e.g., 16 hours = 2 days).

Employee: David Miller (EMP012)
Status: Probation Passed
- Annual Leave: 80 hours
- Sick Leave: 40 hours

Employee: Sarah Jenkins (EMP013)
Status: PROBATION EXTENDED
- Action: Do NOT allocate any leave at this time. Wait for 30-day review.

Employee: Marcus Chen (EMP017)
Status: Probation Passed
- Annual Leave: 64 hours
- Sick Leave: 32 hours

Employee: Elena Rostova (EMP019)
Status: Probation Passed
- Annual Leave: 96 hours
- Sick Leave: 48 hours
EOF

chown ga:ga /home/ga/Desktop/leave_allocation_memo.txt

log "Setting up UI..."
# Ensure browser is ready at the dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="