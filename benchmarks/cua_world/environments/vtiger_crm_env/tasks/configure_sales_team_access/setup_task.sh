#!/bin/bash
echo "=== Setting up configure_sales_team_access task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing artifacts from previous test runs
echo "Cleaning up any pre-existing task artifacts..."
USERID=$(vtiger_db_query "SELECT id FROM vtiger_users WHERE user_name='sarah.mitchell' LIMIT 1" | tr -d '[:space:]')
if [ -n "$USERID" ]; then
    vtiger_db_query "DELETE FROM vtiger_users WHERE id='$USERID'"
    vtiger_db_query "DELETE FROM vtiger_user2role WHERE userid='$USERID'"
fi

ROLEID=$(vtiger_db_query "SELECT roleid FROM vtiger_role WHERE rolename='Junior Sales Rep' LIMIT 1" | tr -d '[:space:]')
if [ -n "$ROLEID" ]; then
    vtiger_db_query "DELETE FROM vtiger_role WHERE roleid='$ROLEID'"
    vtiger_db_query "DELETE FROM vtiger_role2profile WHERE roleid='$ROLEID'"
fi

PROFILEID=$(vtiger_db_query "SELECT profileid FROM vtiger_profile WHERE profilename='Junior Sales Access' LIMIT 1" | tr -d '[:space:]')
if [ -n "$PROFILEID" ]; then
    vtiger_db_query "DELETE FROM vtiger_profile WHERE profileid='$PROFILEID'"
    vtiger_db_query "DELETE FROM vtiger_profile2tab WHERE profileid='$PROFILEID'"
fi

# 2. Record Initial Counts
INIT_PROFILES=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_profile" | tr -d '[:space:]')
INIT_ROLES=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_role" | tr -d '[:space:]')
INIT_USERS=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_users" | tr -d '[:space:]')

cat > /tmp/initial_counts.json << EOF
{
  "profiles": ${INIT_PROFILES:-0},
  "roles": ${INIT_ROLES:-0},
  "users": ${INIT_USERS:-0}
}
EOF

# 3. Ensure logged in and navigate to CRM Settings index
# Settings page is the perfect starting point for administrative tasks
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Settings&action=index&parenttab=Settings"
sleep 4

# 4. Take initial screenshot
take_screenshot /tmp/configure_sales_initial.png

echo "=== configure_sales_team_access task setup complete ==="
echo "Initial counts recorded: Profiles: $INIT_PROFILES | Roles: $INIT_ROLES | Users: $INIT_USERS"