#!/bin/bash
echo "=== Setting up escalate_support_ticket task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Ensure Support Group exists
SUPPORT_GROUP_ID=$(vtiger_db_query "SELECT groupid FROM vtiger_groups WHERE groupname='Support Group' LIMIT 1" | tr -d '[:space:]')
if [ -z "$SUPPORT_GROUP_ID" ]; then
    echo "Support Group missing, creating..."
    vtiger_db_query "INSERT INTO vtiger_groups (groupid, groupname, description) VALUES (4, 'Support Group', 'Support Team')"
    SUPPORT_GROUP_ID=4
fi

# Get admin user ID
ADMIN_ID=$(vtiger_db_query "SELECT id FROM vtiger_users WHERE user_name='admin' LIMIT 1" | tr -d '[:space:]')
if [ -z "$ADMIN_ID" ]; then
    ADMIN_ID=1
fi

# Clean up any existing ticket with this name
vtiger_db_query "DELETE FROM vtiger_crmentity WHERE label='Payment Gateway Integration Failure'"
vtiger_db_query "DELETE FROM vtiger_troubletickets WHERE title='Payment Gateway Integration Failure'"

# Create the ticket safely via raw SQL to bypass PHP overhead and guarantee availability
NEW_ID=99901
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($NEW_ID, $ADMIN_ID, $ADMIN_ID, 'HelpDesk', NOW(), NOW(), 1, 0, 'Payment Gateway Integration Failure')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, status, title, priority, severity) VALUES ($NEW_ID, 'TT99901', 'Open', 'Payment Gateway Integration Failure', 'High', 'Major')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($NEW_ID)"

echo "$NEW_ID" > /tmp/target_ticket_id.txt
chmod 666 /tmp/target_ticket_id.txt

# Ensure logged in and navigate to Tickets list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=HelpDesk&view=List"
sleep 3

# Take initial screenshot
take_screenshot /tmp/escalate_ticket_initial.png

echo "=== escalate_support_ticket task setup complete ==="
echo "Task: Escalate ticket 'Payment Gateway Integration Failure'"
echo "Starting Priority: High, Assigned: admin"