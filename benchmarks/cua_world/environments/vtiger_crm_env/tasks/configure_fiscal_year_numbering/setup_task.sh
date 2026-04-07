#!/bin/bash
echo "=== Setting up configure_fiscal_year_numbering task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset custom record numbering for Quotes, Invoice, PurchaseOrder to default standard states
echo "Resetting custom record numbering settings..."
vtiger_db_query "UPDATE vtiger_modentity_num SET prefix='QUO', cur_id=1 WHERE semodule='Quotes'"
vtiger_db_query "UPDATE vtiger_modentity_num SET prefix='INV', cur_id=1 WHERE semodule='Invoice'"
vtiger_db_query "UPDATE vtiger_modentity_num SET prefix='PO', cur_id=1 WHERE semodule='PurchaseOrder'"

# Delete any existing test quotes with the target subject to ensure a clean slate
echo "Cleaning up any old test quotes..."
EXISTING_QUOTE=$(vtiger_db_query "SELECT quoteid FROM vtiger_quotes WHERE subject='FY2026 Numbering Test' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_QUOTE" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_QUOTE"
    vtiger_db_query "DELETE FROM vtiger_quotes WHERE quoteid=$EXISTING_QUOTE"
fi

# Ensure logged in and navigate to Vtiger Dashboard
echo "Logging in and navigating to dashboard..."
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 4

# Take initial screenshot for evidence
take_screenshot /tmp/fiscal_numbering_initial.png

echo "=== configure_fiscal_year_numbering task setup complete ==="