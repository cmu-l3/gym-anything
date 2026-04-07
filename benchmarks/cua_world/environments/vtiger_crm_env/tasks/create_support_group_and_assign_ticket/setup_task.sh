#!/bin/bash
echo "=== Setting up create_support_group_and_assign_ticket task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Cleanup existing group if it exists
GROUP_ID=$(vtiger_db_query "SELECT groupid FROM vtiger_groups WHERE groupname='Tier 2 Billing Escalations' LIMIT 1" | tr -d '[:space:]')
if [ -n "$GROUP_ID" ]; then
    echo "WARNING: Group already exists, removing"
    vtiger_db_query "DELETE FROM vtiger_users2group WHERE groupid=$GROUP_ID"
    vtiger_db_query "DELETE FROM vtiger_group2role WHERE groupid=$GROUP_ID"
    vtiger_db_query "DELETE FROM vtiger_group2rs WHERE groupid=$GROUP_ID"
    vtiger_db_query "DELETE FROM vtiger_group2modules WHERE groupid=$GROUP_ID"
    vtiger_db_query "DELETE FROM vtiger_groups WHERE groupid=$GROUP_ID"
fi

# 2. Cleanup existing ticket if it exists
TICKET_ID=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets WHERE title='Disputed Charge on Invoice #8472' LIMIT 1" | tr -d '[:space:]')
if [ -n "$TICKET_ID" ]; then
    echo "WARNING: Ticket already exists, removing"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$TICKET_ID"
    vtiger_db_query "DELETE FROM vtiger_troubletickets WHERE ticketid=$TICKET_ID"
fi

# 3. Ensure logged in and navigate to Home
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_support_group_initial.png

echo "=== Setup complete ==="
echo "Task: Create support group and assign a new ticket to it."