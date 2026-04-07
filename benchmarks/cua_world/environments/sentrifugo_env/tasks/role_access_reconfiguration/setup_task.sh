#!/bin/bash
echo "=== Setting up role_access_reconfiguration task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start timestamp for verification
date +%s > /tmp/task_start_timestamp

# ---- Clean up prior run artifacts & ensure clean state ----
log "Cleaning up target roles from any prior runs..."
sentrifugo_db_root_query "DELETE FROM main_roles WHERE rolename IN ('Team Lead', 'Finance Clerk', 'Program Coordinator');" 2>/dev/null || true

# Find the default "Employee" role ID (or fallback to ID 4)
DEFAULT_ROLE_ID=$(sentrifugo_db_query "SELECT id FROM main_roles WHERE rolename='Employee' LIMIT 1;" | tr -d '[:space:]')
if [ -z "$DEFAULT_ROLE_ID" ]; then
    DEFAULT_ROLE_ID=4
fi

log "Resetting target employees to default role (ID: $DEFAULT_ROLE_ID)..."
for EMPID in EMP005 EMP009 EMP014 EMP017; do
    # Sentrifugo typically uses role_id in main_users, but sometimes userrole depending on the version. We update both if they exist.
    sentrifugo_db_root_query "UPDATE main_users SET role_id=${DEFAULT_ROLE_ID} WHERE employeeId='${EMPID}';" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_users SET userrole=${DEFAULT_ROLE_ID} WHERE employeeId='${EMPID}';" 2>/dev/null || true
done

# ---- Create the access control memo on the Desktop ----
log "Creating access control memo on Desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/access_control_memo.txt << 'MEMO'
INTERNAL MEMO — IT Audit Compliance Action Items
Date: 2026-01-15
From: IT Audit Committee
To: HR Systems Administrator
Subject: Role-Based Access Control Remediation

Per Finding #2024-IT-07, the following access control changes must be
implemented in Sentrifugo HRMS immediately to pass compliance:

STEP 1: Create the following custom roles
=========================================

Role Name: Team Lead
Description: Mid-level supervisory role for team management and leave approvals

Role Name: Finance Clerk
Description: Financial operations support role for expense and payroll processing

Role Name: Program Coordinator
Description: Program management role for project tracking and reporting

STEP 2: Reassign employees to new roles
========================================

Employee ID | Employee Name      | New Role
----------- | ------------------ | -------------------
EMP005      | Sarah Thompson     | Team Lead
EMP009      | David Kim          | Finance Clerk
EMP014      | Amanda Foster      | Program Coordinator
EMP017      | Christopher Lee    | Team Lead

NOTE: Do NOT delete or modify any existing default roles.
Only create the three new roles and reassign the four employees listed above.
MEMO

chown ga:ga /home/ga/Desktop/access_control_memo.txt

# ---- Launch Firefox and log in, navigating to Roles page ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/index.php/roles"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task setup complete. Target roles deleted, employees reset, memo on Desktop."
echo "=== Setup complete ==="