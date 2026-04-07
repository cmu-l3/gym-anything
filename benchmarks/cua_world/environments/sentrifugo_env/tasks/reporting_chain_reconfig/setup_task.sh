#!/bin/bash
echo "=== Setting up reporting_chain_reconfig task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_time.txt

# Get user IDs for employees to modify
EMP002_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP002' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP006_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP006' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP010_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP010' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP012_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP012' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
EMP014_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP014' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')

# Get user IDs for initial incorrect managers
JAMES_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='James' AND lastname='Anderson' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
MICHAEL_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Michael' AND lastname='Davis' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
DAVID_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='David' AND lastname='Kim' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')

# Set initial incorrect managers to simulate the starting state
if [ -n "$EMP002_ID" ] && [ -n "$JAMES_ID" ]; then
    sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${JAMES_ID} WHERE user_id=${EMP002_ID};" 2>/dev/null || true
fi
if [ -n "$EMP006_ID" ] && [ -n "$JAMES_ID" ]; then
    sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${JAMES_ID} WHERE user_id=${EMP006_ID};" 2>/dev/null || true
fi
if [ -n "$EMP010_ID" ] && [ -n "$MICHAEL_ID" ]; then
    sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${MICHAEL_ID} WHERE user_id=${EMP010_ID};" 2>/dev/null || true
fi
if [ -n "$EMP012_ID" ] && [ -n "$DAVID_ID" ]; then
    sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${DAVID_ID} WHERE user_id=${EMP012_ID};" 2>/dev/null || true
fi
if [ -n "$EMP014_ID" ] && [ -n "$JAMES_ID" ]; then
    sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${JAMES_ID} WHERE user_id=${EMP014_ID};" 2>/dev/null || true
fi

# Export initial state to verify against do-nothing submissions
cat > /tmp/initial_reporting_managers.json << EOF
{
    "EMP002": "${JAMES_ID:-}",
    "EMP006": "${JAMES_ID:-}",
    "EMP010": "${MICHAEL_ID:-}",
    "EMP012": "${DAVID_ID:-}",
    "EMP014": "${JAMES_ID:-}"
}
EOF

# Drop memo on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/reporting_restructure_memo.txt << 'MEMO'
MEMORANDUM

TO:      HR Administration
FROM:    VP of Operations
DATE:    2026-01-15
SUBJECT: Mid-Year Reporting Structure Update — Effective Immediately

Following the Q1 divisional realignment, the following reporting manager
changes must be entered into Sentrifugo before end of business today.

EMPLOYEE REASSIGNMENTS:
─────────────────────────────────────────────────────────────────
 Employee ID | Employee Name       | Current Manager   | New Reporting Manager
─────────────────────────────────────────────────────────────────
 EMP002      | Sarah Mitchell      | James Anderson    | Jessica Liu
 EMP006      | Jessica Liu         | James Anderson    | Christopher Lee
 EMP010      | Rachel Green        | Michael Davis     | Thomas Wright
 EMP012      | Jennifer Martinez   | David Kim         | Amanda Torres
 EMP014      | Sophia Brown        | James Anderson    | David Kim
─────────────────────────────────────────────────────────────────

IMPORTANT: Only the Reporting Manager field should be changed.
Do NOT modify department, job title, or any other employee fields.

Please confirm completion by end of day.

— VP of Operations
MEMO

chown ga:ga /home/ga/Desktop/reporting_restructure_memo.txt
log "Restructure memo created at ~/Desktop/reporting_restructure_memo.txt"

# Navigate to employee list
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3
take_screenshot /tmp/task_start.png

log "Task ready: reporting managers pre-set to incorrect state, memo on Desktop"
echo "=== reporting_chain_reconfig task setup complete ==="