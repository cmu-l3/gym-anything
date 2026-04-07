#!/bin/bash
echo "=== Setting up define_opportunity_buying_center task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# 2. Clean up potential existing records
echo "Cleaning up existing data..."
suitecrm_db_query "DELETE FROM accounts_opportunities WHERE opportunity_id='opp-apex-001';"
suitecrm_db_query "DELETE FROM accounts_contacts WHERE account_id='acc-apex-001';"
suitecrm_db_query "DELETE FROM opportunities_contacts WHERE opportunity_id='opp-apex-001';"
suitecrm_db_query "DELETE FROM opportunities WHERE id='opp-apex-001' OR name='Apex Q4 Supply Chain Automation';"
suitecrm_db_query "DELETE FROM accounts WHERE id='acc-apex-001' OR name='Apex Logistics International';"
suitecrm_db_query "DELETE FROM contacts WHERE id IN ('con-eleanor-001', 'con-marcus-001', 'con-david-001') OR (first_name='Eleanor' AND last_name='Vance') OR (first_name='Marcus' AND last_name='Thorne') OR (first_name='David' AND last_name='Chen');"

# 3. Insert deterministic seed records
echo "Inserting fresh data..."
suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('acc-apex-001', 'Apex Logistics International', NOW(), NOW(), '1', '1', 0);"
suitecrm_db_query "INSERT INTO opportunities (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, amount, sales_stage) VALUES ('opp-apex-001', 'Apex Q4 Supply Chain Automation', NOW(), NOW(), '1', '1', 0, 250000, 'Prospecting');"
suitecrm_db_query "INSERT INTO accounts_opportunities (id, opportunity_id, account_id, date_modified, deleted) VALUES ('acc-opp-apex-001', 'opp-apex-001', 'acc-apex-001', NOW(), 0);"
suitecrm_db_query "INSERT INTO contacts (id, first_name, last_name, title, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('con-eleanor-001', 'Eleanor', 'Vance', 'CEO', NOW(), NOW(), '1', '1', 0), ('con-marcus-001', 'Marcus', 'Thorne', 'CFO', NOW(), NOW(), '1', '1', 0), ('con-david-001', 'David', 'Chen', 'IT Director', NOW(), NOW(), '1', '1', 0);"
suitecrm_db_query "INSERT INTO accounts_contacts (id, contact_id, account_id, date_modified, deleted) VALUES ('acc-con-el-001', 'con-eleanor-001', 'acc-apex-001', NOW(), 0), ('acc-con-ma-001', 'con-marcus-001', 'acc-apex-001', NOW(), 0), ('acc-con-da-001', 'con-david-001', 'acc-apex-001', NOW(), 0);"

# 4. Ensure logged in and navigate to Opportunities list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Opportunities&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== setup complete ==="