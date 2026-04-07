#!/bin/bash
echo "=== Setting up configure_lead_conversion_mapping task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing data that might interfere with this test
echo "Cleaning up potential pre-existing test data..."
# Delete the OConnor test lead
LEAD_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE setype='Leads' AND label LIKE '%OConnor%'" | head -1 | tr -d '[:space:]')
if [ -n "$LEAD_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$LEAD_ID"
    vtiger_db_query "DELETE FROM vtiger_leaddetails WHERE leadid=$LEAD_ID"
fi

# Delete the OConnor test contact
CONTACT_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE setype='Contacts' AND label LIKE '%OConnor%'" | head -1 | tr -d '[:space:]')
if [ -n "$CONTACT_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$CONTACT_ID"
    vtiger_db_query "DELETE FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID"
fi

# Remove 'Referral Code' fields if they already exist from previous runs
vtiger_db_query "DELETE FROM vtiger_field WHERE fieldlabel='Referral Code'"
# Note: we don't drop the dynamically created columns (cf_XXX) as Vtiger handles ignoring them if they aren't in vtiger_field,
# and dropping columns dynamically in a setup script can be error-prone. 
# Vtiger simply allocates a new cf_XXX column when a field is re-added.

# Remove mapping entry if it exists
vtiger_db_query "DELETE FROM vtiger_convertleadmapping WHERE contactfid NOT IN (SELECT fieldid FROM vtiger_field) OR leadfid NOT IN (SELECT fieldid FROM vtiger_field)"

# 2. Ensure logged in and navigate to Vtiger CRM Settings page
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Vtiger&parent=Settings&view=Index"
sleep 3

# 3. Take initial screenshot
take_screenshot /tmp/configure_mapping_initial.png

echo "=== configure_lead_conversion_mapping task setup complete ==="