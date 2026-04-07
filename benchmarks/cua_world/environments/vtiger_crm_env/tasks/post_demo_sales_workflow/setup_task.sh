#!/bin/bash
echo "=== Setting up post_demo_sales_workflow task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any existing artifacts from previous runs
vtiger_db_query "DELETE FROM vtiger_crmentity WHERE label IN ('Product Demo and Q&A', 'Draft and Send Enterprise Proposal');"
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject IN ('Product Demo and Q&A', 'Draft and Send Enterprise Proposal');"

# 2. Ensure target Account (GlobalTech) exists
ACC_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE label='GlobalTech' AND setype='Accounts' LIMIT 1" | tr -d '[:space:]')
if [ -z "$ACC_ID" ]; then
    vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = id + 1;"
    ACC_ID=$(vtiger_db_query "SELECT id FROM vtiger_crmentity_seq" | tr -d '[:space:]')
    vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($ACC_ID, 1, 1, 'Accounts', NOW(), NOW(), 1, 0, 'GlobalTech');"
    vtiger_db_query "INSERT INTO vtiger_account (accountid, accountname) VALUES ($ACC_ID, 'GlobalTech');"
    vtiger_db_query "INSERT INTO vtiger_accountbillads (accountaddressid) VALUES ($ACC_ID);"
    vtiger_db_query "INSERT INTO vtiger_accountshipads (accountaddressid) VALUES ($ACC_ID);"
    vtiger_db_query "INSERT INTO vtiger_accountscf (accountid) VALUES ($ACC_ID);"
fi

# 3. Ensure target Opportunity exists and is in starting state
POT_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE label='GlobalTech - Enterprise Software License' AND setype='Potentials' LIMIT 1" | tr -d '[:space:]')
if [ -z "$POT_ID" ]; then
    vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = id + 1;"
    POT_ID=$(vtiger_db_query "SELECT id FROM vtiger_crmentity_seq" | tr -d '[:space:]')
    vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($POT_ID, 1, 1, 'Potentials', DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY), 1, 0, 'GlobalTech - Enterprise Software License');"
    vtiger_db_query "INSERT INTO vtiger_potential (potentialid, potentialname, related_to, amount, closingdate, sales_stage, probability) VALUES ($POT_ID, 'GlobalTech - Enterprise Software License', $ACC_ID, 150000, '2026-12-31', 'Needs Analysis', 20);"
    vtiger_db_query "INSERT INTO vtiger_potentialscf (potentialid) VALUES ($POT_ID);"
else
    # Reset to starting state
    vtiger_db_query "UPDATE vtiger_potential SET sales_stage='Needs Analysis', probability=20 WHERE potentialid=$POT_ID;"
    vtiger_db_query "UPDATE vtiger_crmentity SET modifiedtime=DATE_SUB(NOW(), INTERVAL 2 DAY) WHERE crmid=$POT_ID;"
fi

# 4. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# 5. Ensure logged in and navigate to Opportunities/Potentials list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== post_demo_sales_workflow task setup complete ==="
echo "Target Deal: GlobalTech - Enterprise Software License (ID: $POT_ID)"