#!/bin/bash
set -e
echo "=== Setting up task: Add Custom Field to Organizations ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial custom field count for Accounts module
ACCOUNTS_TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Accounts'" | tr -d '[:space:]')
echo "Accounts module tabid: $ACCOUNTS_TABID"

if [ -z "$ACCOUNTS_TABID" ] || [ "$ACCOUNTS_TABID" = "" ]; then
    echo "WARNING: Could not find Accounts module tabid, defaulting to 6"
    ACCOUNTS_TABID=6
fi

# Store tabid for verifier
echo "$ACCOUNTS_TABID" > /tmp/accounts_tabid.txt

# Check that no "Customer Tier" field already exists (clean state)
EXISTING=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_field WHERE fieldlabel='Customer Tier' AND tabid=${ACCOUNTS_TABID}" | tr -d '[:space:]')
if [ "$EXISTING" -gt 0 ]; then
    echo "WARNING: 'Customer Tier' field already exists. Removing for clean state..."
    FIELD_NAME=$(vtiger_db_query "SELECT fieldname FROM vtiger_field WHERE fieldlabel='Customer Tier' AND tabid=${ACCOUNTS_TABID} LIMIT 1" | tr -d '[:space:]')
    if [ -n "$FIELD_NAME" ]; then
        vtiger_db_query "DELETE FROM vtiger_field WHERE fieldname='${FIELD_NAME}' AND tabid=${ACCOUNTS_TABID}" || true
        vtiger_db_query "DROP TABLE IF EXISTS vtiger_${FIELD_NAME}" || true
        vtiger_db_query "DROP TABLE IF EXISTS vtiger_${FIELD_NAME}_seq" || true
        # Remove column from accountscf if exists
        vtiger_db_query "ALTER TABLE vtiger_accountscf DROP COLUMN IF EXISTS ${FIELD_NAME}" || true
    fi
fi

# Calculate and record initial field count for Accounts
INITIAL_FIELD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_field WHERE tabid=${ACCOUNTS_TABID}" | tr -d '[:space:]')
echo "$INITIAL_FIELD_COUNT" > /tmp/initial_field_count.txt
echo "Initial field count for Accounts: $INITIAL_FIELD_COUNT"

# Ensure Firefox is running and logged into Vtiger at the dashboard
echo "--- Ensuring Firefox is logged in ---"
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Agent should now add a 'Customer Tier' picklist field to the Organizations module."