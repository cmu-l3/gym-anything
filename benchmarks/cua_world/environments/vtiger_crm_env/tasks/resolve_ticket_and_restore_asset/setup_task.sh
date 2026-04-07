#!/bin/bash
echo "=== Setting up resolve_ticket_and_restore_asset task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Remove any pre-existing duplicates to ensure a clean state
EXISTING_ASSET=$(vtiger_db_query "SELECT assetsid FROM vtiger_assets WHERE assetname='Mower ZTR-5000-A1' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_ASSET" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_ASSET"
    vtiger_db_query "DELETE FROM vtiger_assets WHERE assetsid=$EXISTING_ASSET"
fi

EXISTING_TICKET=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets WHERE title='URGENT: Broken Blade on Mower' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_TICKET" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_TICKET"
    vtiger_db_query "DELETE FROM vtiger_troubletickets WHERE ticketid=$EXISTING_TICKET"
fi

# Programmatically generate new records via direct database inserts to guarantee existence
NEXT_ID=$(vtiger_db_query "SELECT id FROM vtiger_crmentity_seq LIMIT 1" | tr -d '[:space:]')
if [ -z "$NEXT_ID" ]; then
    NEXT_ID=10000 # Fallback
fi

ASSET_ID=$((NEXT_ID + 1))
TICKET_ID=$((NEXT_ID + 2))
NEW_SEQ=$((NEXT_ID + 3))

# Update sequence
vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = $NEW_SEQ"

# Insert Asset Record
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, viewedtime, status, version, presence, deleted, label) VALUES ($ASSET_ID, 1, 1, 1, 'Assets', '', NOW(), NOW(), NULL, '', 0, 1, 0, 'Mower ZTR-5000-A1')"
vtiger_db_query "INSERT INTO vtiger_assets (assetsid, asset_no, assetname, dateinservice, assetstatus) VALUES ($ASSET_ID, 'AST-$ASSET_ID', 'Mower ZTR-5000-A1', '2024-01-01', 'Out-of-service')"
vtiger_db_query "INSERT INTO vtiger_assetscf (assetsid) VALUES ($ASSET_ID)"

# Insert Ticket Record
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, viewedtime, status, version, presence, deleted, label) VALUES ($TICKET_ID, 1, 1, 1, 'HelpDesk', '', NOW(), NOW(), NULL, '', 0, 1, 0, 'URGENT: Broken Blade on Mower')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, status, title) VALUES ($TICKET_ID, 'TT-$TICKET_ID', 'Open', 'URGENT: Broken Blade on Mower')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($TICKET_ID)"

# Save entity IDs for the export script
echo "ASSET_ID=$ASSET_ID" > /tmp/task_entity_ids.txt
echo "TICKET_ID=$TICKET_ID" >> /tmp/task_entity_ids.txt

# Ensure Firefox is logged into Vtiger and at the Dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# Take initial screenshot for reference
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="
echo "Target Ticket ID: $TICKET_ID"
echo "Target Asset ID: $ASSET_ID"