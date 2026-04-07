#!/bin/bash
echo "=== Setting up workforce_classification_update task ==="

source /workspace/scripts/task_utils.sh

# Wait for HTTP readiness
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming (comparing creation timestamps)
date +%s > /tmp/task_start_time.txt

log "Cleaning up prior run artifacts..."

# Remove target statuses if they already exist
sentrifugo_db_root_query "DELETE FROM main_employmentstatus WHERE statusname IN ('Consultant', 'Secondment', 'Fixed-Term Contract');" 2>/dev/null || true

# Remove target prefixes if they already exist (checking both common column names)
sentrifugo_db_root_query "DELETE FROM main_prefix WHERE prefixname IN ('Mx.', 'Prof.') OR prefix IN ('Mx.', 'Prof.');" 2>/dev/null || true

# Reset target employees to 'Full-time Permanent' (or ID 1)
FT_ID=$(sentrifugo_db_query "SELECT id FROM main_employmentstatus WHERE statusname LIKE '%Full%time%' LIMIT 1;" | tr -d '[:space:]')
if [ -z "$FT_ID" ]; then
    FT_ID=$(sentrifugo_db_query "SELECT id FROM main_employmentstatus LIMIT 1;" | tr -d '[:space:]')
    if [ -z "$FT_ID" ]; then FT_ID=1; fi
fi

for EMPID in EMP005 EMP009 EMP013 EMP016; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        # Update across all possible user detail tables
        sentrifugo_db_root_query "UPDATE main_users SET employmentstatus_id=${FT_ID} WHERE id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "UPDATE main_users SET empstatus_id=${FT_ID} WHERE id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "UPDATE main_employees SET employmentstatus_id=${FT_ID} WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "UPDATE main_employees_summary SET employmentstatus_id=${FT_ID}, employmentstatus_name='Full-time Permanent' WHERE user_id=${UID_VAL};" 2>/dev/null || true
    fi
done

log "Initial database cleanup complete."

# Capture initial counts for anti-gaming
INITIAL_STATUS_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_employmentstatus;" | tr -d '[:space:]')
INITIAL_PREFIX_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_prefix;" | tr -d '[:space:]')

cat > /tmp/workforce_counts.json << EOF
{
    "initial_status_count": ${INITIAL_STATUS_COUNT:-0},
    "initial_prefix_count": ${INITIAL_PREFIX_COUNT:-0}
}
EOF
chmod 666 /tmp/workforce_counts.json

# Create the directive document on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/workforce_classification_directive.txt << 'EOF'
WORKFORCE CLASSIFICATION STANDARDIZATION DIRECTIVE
Issued by: Chief Human Resources Officer
Effective: Immediately
Reference: WC-2026-001

PART A — NEW EMPLOYMENT STATUS TYPES
Create the following employment status types in the HRMS:
  1. Consultant
  2. Secondment
  3. Fixed-Term Contract

PART B — NEW EMPLOYEE PREFIXES
Create the following employee prefixes in the HRMS:
  1. Mx.
  2. Prof.

PART C — EMPLOYEE RECLASSIFICATION
Update the following employees' employment status:

  Employee ID | Name              | New Employment Status
  ------------|-------------------|----------------------
  EMP005      | Sarah Thompson    | Consultant
  EMP009      | Kevin O'Brien     | Fixed-Term Contract
  EMP013      | Daniel Wilson     | Secondment
  EMP016      | Amanda Foster     | Consultant

All other employee records remain unchanged. Do not deactivate or 
delete any existing employment status types.
EOF
chown ga:ga /home/ga/Desktop/workforce_classification_directive.txt
log "Directive document created at ~/Desktop/workforce_classification_directive.txt"

# Ensure Firefox is open and logged into Sentrifugo
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start_screenshot.png ga

log "Task setup complete. Ready for agent execution."