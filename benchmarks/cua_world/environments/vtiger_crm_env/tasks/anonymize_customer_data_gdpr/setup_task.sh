#!/bin/bash
echo "=== Setting up anonymize_customer_data_gdpr task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Injecting target 'Marcus Sterling' records into CRM database..."

# 1. Insert Lead for Marcus Sterling
vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = id + 1;"
LEAD_ID=$(vtiger_db_query "SELECT id FROM vtiger_crmentity_seq;" | tr -d '[:space:]')
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($LEAD_ID, 1, 1, 1, 'Leads', NOW(), NOW(), 1, 0, 'Marcus Sterling');"
vtiger_db_query "INSERT INTO vtiger_leaddetails (leadid, lead_no, firstname, lastname, company, email, phone, emailoptout, donotcall) VALUES ($LEAD_ID, 'LEA999', 'Marcus', 'Sterling', 'Sterling Enterprises', 'marcus.s@example.com', '555-019-2834', 0, 0);"
vtiger_db_query "INSERT INTO vtiger_leadsubdetails (leadsubscriptionid) VALUES ($LEAD_ID);"
vtiger_db_query "INSERT INTO vtiger_leadaddress (leadaddressid) VALUES ($LEAD_ID);"
vtiger_db_query "INSERT INTO vtiger_leadscf (leadid) VALUES ($LEAD_ID);"

# 2. Insert Contact for Marcus Sterling
vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = id + 1;"
CONTACT_ID=$(vtiger_db_query "SELECT id FROM vtiger_crmentity_seq;" | tr -d '[:space:]')
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($CONTACT_ID, 1, 1, 1, 'Contacts', NOW(), NOW(), 1, 0, 'Marcus Sterling');"
vtiger_db_query "INSERT INTO vtiger_contactdetails (contactid, contact_no, firstname, lastname, email, phone, emailoptout, donotcall) VALUES ($CONTACT_ID, 'CON999', 'Marcus', 'Sterling', 'marcus.s@example.com', '555-019-2834', 0, 0);"
vtiger_db_query "INSERT INTO vtiger_contactsubdetails (contactsubscriptionid) VALUES ($CONTACT_ID);"
vtiger_db_query "INSERT INTO vtiger_contactaddress (contactaddressid, mailingstreet, mailingcity, mailingstate, mailingzip, mailingcountry) VALUES ($CONTACT_ID, '123 Main St', 'Boston', 'MA', '02101', 'USA');"
vtiger_db_query "INSERT INTO vtiger_contactscf (contactid) VALUES ($CONTACT_ID);"

echo "Created Lead ID: $LEAD_ID"
echo "Created Contact ID: $CONTACT_ID"

# Save the target IDs for the export script to use later
cat > /tmp/gdpr_target_ids.json << EOF
{
  "lead_id": $LEAD_ID,
  "contact_id": $CONTACT_ID
}
EOF
chmod 666 /tmp/gdpr_target_ids.json 2>/dev/null || true

# 3. Ensure logged in and navigate to Home or Search
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/gdpr_initial_state.png

echo "=== Setup complete ==="