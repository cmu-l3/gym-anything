#!/bin/bash
echo "=== Setting up create_ticket task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial ticket count
INITIAL_TICKET_COUNT=$(get_ticket_count)
echo "Initial ticket count: $INITIAL_TICKET_COUNT"
rm -f /tmp/initial_ticket_count.txt 2>/dev/null || true
echo "$INITIAL_TICKET_COUNT" > /tmp/initial_ticket_count.txt
chmod 666 /tmp/initial_ticket_count.txt 2>/dev/null || true

# 2. Verify the target ticket does not already exist
EXISTING=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets WHERE title='API gateway returning 503 errors under load' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Ticket already exists, removing"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_troubletickets WHERE ticketid=$EXISTING"
fi

# 3. Ensure logged in and navigate to Tickets list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=HelpDesk&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_ticket_initial.png

echo "=== create_ticket task setup complete ==="
echo "Task: Create ticket 'API gateway returning 503 errors under load'"
echo "Agent should click Add Ticket and fill in the form"
