#!/bin/bash
echo "=== Setting up create_service_and_mixed_quote task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Seed prerequisite data using Vtiger's PHP internal framework
echo "Seeding prerequisite Account, Contact, and Product..."
cat > /tmp/seed_prereqs.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
chdir('/var/www/html/vtigercrm');
$_SERVER['HTTP_HOST'] = 'localhost:8000';
$_SERVER['SERVER_NAME'] = 'localhost';
$_SERVER['SERVER_PORT'] = '8000';

require_once('vendor/autoload.php');
require_once('config.inc.php');
require_once('includes/main/WebUI.php');

// Authenticate as Admin
$user = new Users();
$user->retrieveCurrentUserInfoFromFile(1);
vglobal('current_user', $user);

// Create Account (Organization)
$account = Vtiger_Record_Model::getCleanInstance('Accounts');
$account->set('accountname', 'TechNova Solutions');
$account->set('bill_street', '100 Innovation Way');
$account->set('bill_city', 'San Jose');
$account->set('bill_state', 'CA');
$account->set('bill_code', '95110');
$account->set('ship_street', '100 Innovation Way');
$account->set('ship_city', 'San Jose');
$account->set('ship_state', 'CA');
$account->set('ship_code', '95110');
$account->save();
$accountId = $account->getId();

// Create Contact
$contact = Vtiger_Record_Model::getCleanInstance('Contacts');
$contact->set('firstname', 'David');
$contact->set('lastname', 'Chen');
$contact->set('account_id', $accountId);
$contact->save();

// Create Product
$product = Vtiger_Record_Model::getCleanInstance('Products');
$product->set('productname', 'Cisco Meraki MX68 Router');
$product->set('unit_price', '950.00');
$product->set('qtyinstock', '50');
$product->set('discontinued', '1'); // 1 = Active
$product->save();

echo "Prerequisites successfully created.\n";
?>
PHPEOF

docker cp /tmp/seed_prereqs.php vtiger-app:/tmp/seed_prereqs.php
docker exec vtiger-app php /tmp/seed_prereqs.php

# 3. Record initial record counts
INITIAL_SERVICE_COUNT=$(vtiger_count "vtiger_service" "1=1")
INITIAL_QUOTE_COUNT=$(vtiger_count "vtiger_quotes" "1=1")
echo "$INITIAL_SERVICE_COUNT" > /tmp/initial_service_count.txt
echo "$INITIAL_QUOTE_COUNT" > /tmp/initial_quote_count.txt

# 4. Ensure logged into CRM and at home dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"

# 5. Capture initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="