#!/bin/bash
echo "=== Setting up cross_module_integrity_audit task ==="

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

source /workspace/scripts/task_utils.sh

# 0. Record timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Wait for MariaDB to accept connections
echo "--- Waiting for database ---"
for i in $(seq 1 30); do
    if docker exec suitecrm-db mysqladmin ping -u suitecrm -psuitecrm_pass --silent 2>/dev/null; then
        echo "Database ready after ${i}s"
        break
    fi
    sleep 1
done

# 1. Record baseline
echo "--- Recording baseline ---"
suitecrm_db_query "SELECT id, name, account_type FROM accounts WHERE deleted=0 ORDER BY name" > /tmp/cmi_baseline_accounts.txt
suitecrm_db_query "SELECT id, first_name, last_name, account_id FROM contacts WHERE deleted=0 ORDER BY last_name" > /tmp/cmi_baseline_contacts.txt
chmod 666 /tmp/cmi_baseline_*.txt

# 2. Get account IDs we'll manipulate
APPLE_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Apple Inc.' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
META_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Meta Platforms Inc.' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
EXXON_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='ExxonMobil Corporation' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
MSFT_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Microsoft Corporation' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
ADOBE_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Adobe Inc.' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
SALESFORCE_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Salesforce Inc.' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

# Save IDs for verifier
echo "$APPLE_ID" > /tmp/cmi_apple_id.txt
echo "$META_ID" > /tmp/cmi_meta_id.txt
echo "$EXXON_ID" > /tmp/cmi_exxon_id.txt
echo "$MSFT_ID" > /tmp/cmi_msft_id.txt
echo "$ADOBE_ID" > /tmp/cmi_adobe_id.txt
echo "$SALESFORCE_ID" > /tmp/cmi_salesforce_id.txt
chmod 666 /tmp/cmi_*.txt

# 3. Swap account types to create contradictions
# Apple has Closed Won deal ("Apple - Enterprise Data Platform License") -> should be Customer
# But we set it to Prospect
suitecrm_db_query "UPDATE accounts SET account_type='Prospect' WHERE id='${APPLE_ID}'"
echo "Set Apple Inc. type to Prospect (WRONG - has Closed Won deal)"

# Meta has only Closed Lost deal -> should NOT be Customer
# But we set it to Customer
suitecrm_db_query "UPDATE accounts SET account_type='Customer' WHERE id='${META_ID}'"
echo "Set Meta Platforms Inc. type to Customer (WRONG - no Closed Won deal)"

# ExxonMobil has only Prospecting deal -> should NOT be Customer
# But we set it to Customer
suitecrm_db_query "UPDATE accounts SET account_type='Customer' WHERE id='${EXXON_ID}'"
echo "Set ExxonMobil Corporation type to Customer (WRONG - no Closed Won deal)"

# 4. Create orphan contacts and misattributed contact via PHP
cat > /tmp/cmi_seed.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html');
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

// Orphan contact 1: linked to a non-existent account UUID
$c1 = BeanFactory::newBean('Contacts');
$c1->first_name   = 'Victor';
$c1->last_name    = 'Huang';
$c1->title        = 'Chief Data Officer';
$c1->department   = 'Data Analytics';
$c1->phone_work   = '(650) 253-0150';
$c1->email1       = 'v.huang@abc.xyz';
$c1->account_id   = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
$c1->primary_address_city = 'Mountain View';
$c1->primary_address_state = 'CA';
$c1->description  = 'Primary contact for AI/ML data partnership discussions. Previously met at Google Cloud Next conference.';
$c1->save();
echo "ORPHAN1:" . $c1->id . ":Victor Huang\n";

// Create a temporary account, create orphan contact 2, then soft-delete the account
$phantom = BeanFactory::newBean('Accounts');
$phantom->name = 'Phantom Analytics Corp';
$phantom->industry = 'Technology';
$phantom->account_type = 'Prospect';
$phantom->description = 'Temporary account from import error.';
$phantom->save();
$phantom_id = $phantom->id;

$c2 = BeanFactory::newBean('Contacts');
$c2->first_name   = 'Laura';
$c2->last_name    = 'Fischer';
$c2->title        = 'VP of Analytics';
$c2->department   = 'Business Intelligence';
$c2->phone_work   = '(206) 266-3000';
$c2->email1       = 'l.fischer@amazon.com';
$c2->account_id   = $phantom_id;
$c2->primary_address_city = 'Seattle';
$c2->primary_address_state = 'WA';
$c2->description  = 'Leads the retail analytics division. Key contact for AWS data lake implementation.';
$c2->save();
echo "ORPHAN2:" . $c2->id . ":Laura Fischer\n";

// Soft-delete the phantom account so the contact is orphaned
$db->query("UPDATE accounts SET deleted=1 WHERE id='{$phantom_id}'");
echo "PHANTOM:" . $phantom_id . "\n";

// Misattributed contact: move James Chen from Apple to Microsoft
$apple_id = $db->getOne("SELECT id FROM accounts WHERE name='Apple Inc.' AND deleted=0");
$msft_id  = $db->getOne("SELECT id FROM accounts WHERE name='Microsoft Corporation' AND deleted=0");
$chen_id  = $db->getOne("SELECT id FROM contacts WHERE first_name='James' AND last_name='Chen' AND deleted=0");
if ($chen_id) {
    $db->query("UPDATE contacts SET account_id='{$msft_id}' WHERE id='{$chen_id}'");
    echo "MISATTR:" . $chen_id . ":James Chen:moved from Apple to Microsoft\n";
}
?>
PHPEOF

docker cp /tmp/cmi_seed.php suitecrm-app:/tmp/cmi_seed.php
PHP_OUT=$(docker exec suitecrm-app php /tmp/cmi_seed.php 2>&1)
echo "$PHP_OUT"

# Save IDs
echo "$PHP_OUT" | grep '^ORPHAN1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cmi_orphan1_id.txt
echo "$PHP_OUT" | grep '^ORPHAN2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cmi_orphan2_id.txt
echo "$PHP_OUT" | grep '^MISATTR:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cmi_misattr_id.txt

# Get the Amazon account ID (where Laura Fischer should be reassigned)
AMAZON_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Amazon.com Inc.' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
echo "$AMAZON_ID" > /tmp/cmi_amazon_id.txt

# Get Alphabet/Google account ID (where Victor Huang should be reassigned based on @abc.xyz email)
ALPHABET_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Alphabet Inc.' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
echo "$ALPHABET_ID" > /tmp/cmi_alphabet_id.txt

chmod 666 /tmp/cmi_*.txt

# 5. Ensure logged in and navigate to Accounts
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

take_screenshot /tmp/cmi_initial.png

echo "=== cross_module_integrity_audit setup complete ==="
echo "3 account type mismatches, 2 orphan contacts, 1 misattributed contact"
