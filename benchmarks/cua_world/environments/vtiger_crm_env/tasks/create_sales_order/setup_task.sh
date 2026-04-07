#!/bin/bash
echo "=== Setting up create_sales_order task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Record initial sales order count
INITIAL_SO_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_salesorder" | tr -d '[:space:]' || echo "0")
echo "$INITIAL_SO_COUNT" > /tmp/initial_so_count.txt
echo "Initial Sales Order count: $INITIAL_SO_COUNT"

# 3. Create prerequisite records via PHP
cat > /tmp/setup_so_prereqs.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
ini_set('memory_limit', '256M');

chdir('/var/www/html/vtigercrm');
require_once('vendor/autoload.php');
include_once('config.inc.php');
include_once('vtlib/Vtiger/Utils.php');
include_once('include/utils/utils.php');
include_once('include/Loader.php');
vimport('includes.runtime.EntryPoint');

global $adb, $current_user;
$adb = PearDatabase::getInstance();
$adb->connect();

// Load admin user context
$current_user = CRMEntity::getInstance('Users');
$current_user->retrieveCurrentUserInfoFromFile(Users::getActiveAdminId());

function createEntity($moduleName, $data) {
    global $adb, $current_user;
    $entity = CRMEntity::getInstance($moduleName);
    foreach ($data as $key => $value) {
        $entity->column_fields[$key] = $value;
    }
    $entity->save($moduleName);
    return $entity->id;
}

// Check/Create Organization
$orgCheck = $adb->pquery("SELECT accountid FROM vtiger_account WHERE accountname = ?", array('Greenfield Properties LLC'));
if ($adb->num_rows($orgCheck) == 0) {
    $orgId = createEntity('Accounts', array(
        'accountname' => 'Greenfield Properties LLC',
        'industry' => 'Service',
        'bill_street' => '450 Oak Valley Drive',
        'bill_city' => 'Portland',
        'bill_state' => 'OR',
        'bill_code' => '97201',
        'bill_country' => 'United States',
        'phone' => '503-555-0142',
        'assigned_user_id' => $current_user->id,
    ));
} else {
    $orgId = $adb->query_result($orgCheck, 0, 'accountid');
}

// Check/Create Contact
$contCheck = $adb->pquery("SELECT contactid FROM vtiger_contactdetails WHERE firstname = ? AND lastname = ?", array('Diana', 'Greenfield'));
if ($adb->num_rows($contCheck) == 0) {
    $contId = createEntity('Contacts', array(
        'firstname' => 'Diana',
        'lastname' => 'Greenfield',
        'account_id' => $orgId,
        'email' => 'diana@greenfieldproperties.com',
        'assigned_user_id' => $current_user->id,
    ));
}

// Create Products
$products = array(
    array('productname' => 'Premium Lawn Fertilizer 50lb', 'unit_price' => 45.00, 'qtyinstock' => 500),
    array('productname' => 'Cedar Bark Mulch - Cubic Yard', 'unit_price' => 38.00, 'qtyinstock' => 200),
    array('productname' => 'Irrigation Drip Kit Standard', 'unit_price' => 125.00, 'qtyinstock' => 100),
);

foreach ($products as $prod) {
    $check = $adb->pquery("SELECT productid FROM vtiger_products WHERE productname = ?", array($prod['productname']));
    if ($adb->num_rows($check) == 0) {
        createEntity('Products', array(
            'productname' => $prod['productname'],
            'unit_price' => $prod['unit_price'],
            'qtyinstock' => $prod['qtyinstock'],
            'assigned_user_id' => $current_user->id,
            'discontinued' => 1,
            'product_type' => 'Products',
        ));
    }
}
?>
PHPEOF

docker cp /tmp/setup_so_prereqs.php vtiger-app:/tmp/setup_so_prereqs.php
docker exec vtiger-app php /tmp/setup_so_prereqs.php 2>&1

# 4. Ensure logged in and navigate to the Home dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== create_sales_order task setup complete ==="