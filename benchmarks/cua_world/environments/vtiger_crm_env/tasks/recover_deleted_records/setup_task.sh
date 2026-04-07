#!/bin/bash
echo "=== Setting up recover_deleted_records task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure logged in first so DB is ready
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 2. Clean up any existing records with these names to ensure clean state
echo "Cleaning up existing target records..."
vtiger_db_query "DELETE FROM vtiger_crmentity WHERE label IN ('Red Hat Inc', 'Sun Microsystems', 'Jim Whitehurst', 'Scott McNealy')"

# 3. Create records directly in the database and mark them as deleted (deleted=1)
echo "Injecting deleted records into the database..."
cat > /tmp/setup_records.sql << 'SQLEOF'
-- Red Hat Inc
UPDATE vtiger_crmentity_seq SET id = id + 1;
SELECT @id1 := id FROM vtiger_crmentity_seq;
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, presence, deleted, label) VALUES (@id1, 1, 1, 1, 'Accounts', NOW(), NOW(), 1, 1, 'Red Hat Inc');
INSERT INTO vtiger_account (accountid, accountname) VALUES (@id1, 'Red Hat Inc');
INSERT INTO vtiger_accountbillads (accountaddressid) VALUES (@id1);
INSERT INTO vtiger_accountshipads (accountaddressid) VALUES (@id1);
INSERT INTO vtiger_accountscf (accountid) VALUES (@id1);

-- Sun Microsystems
UPDATE vtiger_crmentity_seq SET id = id + 1;
SELECT @id2 := id FROM vtiger_crmentity_seq;
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, presence, deleted, label) VALUES (@id2, 1, 1, 1, 'Accounts', NOW(), NOW(), 1, 1, 'Sun Microsystems');
INSERT INTO vtiger_account (accountid, accountname) VALUES (@id2, 'Sun Microsystems');
INSERT INTO vtiger_accountbillads (accountaddressid) VALUES (@id2);
INSERT INTO vtiger_accountshipads (accountaddressid) VALUES (@id2);
INSERT INTO vtiger_accountscf (accountid) VALUES (@id2);

-- Jim Whitehurst
UPDATE vtiger_crmentity_seq SET id = id + 1;
SELECT @id3 := id FROM vtiger_crmentity_seq;
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, presence, deleted, label) VALUES (@id3, 1, 1, 1, 'Contacts', NOW(), NOW(), 1, 1, 'Jim Whitehurst');
INSERT INTO vtiger_contactdetails (contactid, firstname, lastname) VALUES (@id3, 'Jim', 'Whitehurst');
INSERT INTO vtiger_contactaddress (contactaddressid) VALUES (@id3);
INSERT INTO vtiger_contactsubdetails (contactsubscriptionid) VALUES (@id3);
INSERT INTO vtiger_contactscf (contactid) VALUES (@id3);

-- Scott McNealy
UPDATE vtiger_crmentity_seq SET id = id + 1;
SELECT @id4 := id FROM vtiger_crmentity_seq;
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, presence, deleted, label) VALUES (@id4, 1, 1, 1, 'Contacts', NOW(), NOW(), 1, 1, 'Scott McNealy');
INSERT INTO vtiger_contactdetails (contactid, firstname, lastname) VALUES (@id4, 'Scott', 'McNealy');
INSERT INTO vtiger_contactaddress (contactaddressid) VALUES (@id4);
INSERT INTO vtiger_contactsubdetails (contactsubscriptionid) VALUES (@id4);
INSERT INTO vtiger_contactscf (contactid) VALUES (@id4);
SQLEOF

docker cp /tmp/setup_records.sql vtiger-db:/tmp/setup_records.sql
docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -e "source /tmp/setup_records.sql"

# 4. Extract IDs to verify the agent restores the EXACT records (Anti-Gaming)
echo "Extracting baseline IDs..."
RED_HAT_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE label='Red Hat Inc' AND setype='Accounts' LIMIT 1" | tr -d '[:space:]')
SUN_MICRO_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE label='Sun Microsystems' AND setype='Accounts' LIMIT 1" | tr -d '[:space:]')
JIM_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE label='Jim Whitehurst' AND setype='Contacts' LIMIT 1" | tr -d '[:space:]')
SCOTT_ID=$(vtiger_db_query "SELECT crmid FROM vtiger_crmentity WHERE label='Scott McNealy' AND setype='Contacts' LIMIT 1" | tr -d '[:space:]')

cat > /tmp/target_ids.json << JSONEOF
{
  "red_hat": "$RED_HAT_ID",
  "sun_micro": "$SUN_MICRO_ID",
  "jim": "$JIM_ID",
  "scott": "$SCOTT_ID"
}
JSONEOF
chmod 666 /tmp/target_ids.json

# 5. Navigate to Home dashboard to start the task
navigate_firefox_to "http://localhost:8000/index.php"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/recover_records_initial.png

echo "=== recover_deleted_records task setup complete ==="
echo "Records Red Hat Inc, Sun Microsystems, Jim Whitehurst, Scott McNealy have been placed in the Recycle Bin."