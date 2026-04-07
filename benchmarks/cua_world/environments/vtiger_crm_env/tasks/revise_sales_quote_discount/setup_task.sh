#!/bin/bash
echo "=== Setting up revise_sales_quote_discount task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a robust PHP script to inject the original quote using Vtiger APIs
cat > /tmp/inject_quote.php << 'PHPEOF'
<?php
error_reporting(E_ERROR);
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';

$current_user = Users::getActiveAdminUser();
vglobal('current_user', $current_user);
$adb = PearDatabase::getInstance();

// 1. Ensure we have a product
$prodRes = $adb->pquery("SELECT productid, unit_price FROM vtiger_products LIMIT 1", array());
if ($adb->num_rows($prodRes) == 0) {
    $prod = Vtiger_Record_Model::getCleanInstance('Products');
    $prod->set('productname', 'Enterprise Server Model X');
    $prod->set('unit_price', 5000);
    $prod->save();
    $prodId = $prod->getId();
    $price = 5000;
} else {
    $prodId = $adb->query_result($prodRes, 0, 'productid');
    $price = $adb->query_result($prodRes, 0, 'unit_price');
    if(empty($price)) $price = 5000;
}

// 2. Ensure we have an account
$accRes = $adb->pquery("SELECT accountid FROM vtiger_account LIMIT 1", array());
if ($adb->num_rows($accRes) == 0) {
    $acc = Vtiger_Record_Model::getCleanInstance('Accounts');
    $acc->set('accountname', 'Enterprise Corp');
    $acc->save();
    $accId = $acc->getId();
} else {
    $accId = $adb->query_result($accRes, 0, 'accountid');
}

// 3. Delete existing target quotes to guarantee clean state
$adb->pquery("UPDATE vtiger_crmentity SET deleted=1 WHERE setype='Quotes' AND label LIKE 'Q3 Hardware Refresh%'", array());

// 4. Create the Original Quote
// We inject the line item via $_REQUEST as Vtiger's Save model relies on it for inventory modules
$_REQUEST['action'] = 'Save';
$_REQUEST['module'] = 'Quotes';
$_REQUEST['totalProductCount'] = 1;
$_REQUEST['deleted1'] = '0';
$_REQUEST['searchIcon1'] = $prodId;
$_REQUEST['hdnProductId1'] = $prodId;
$_REQUEST['qty1'] = 1;
$_REQUEST['listPrice1'] = $price;
$_REQUEST['itemComment1'] = 'Initial hardware request';
$_REQUEST['lineItemType1'] = 'Products';
$_REQUEST['discount_type_final'] = 'zero';
$_REQUEST['hdnDiscountPercent'] = '0';
$_REQUEST['hdnDiscountAmount'] = '0';
$_REQUEST['tax1_percentage'] = '0';

$quote = Vtiger_Record_Model::getCleanInstance('Quotes');
$quote->set('subject', 'Q3 Hardware Refresh');
$quote->set('quotestage', 'Delivered');
$quote->set('account_id', $accId);
$quote->set('currency_id', 1);
$quote->set('conversion_rate', 1);

try {
    $quote->save();
    echo "Successfully injected original quote: " . $quote->getId() . "\n";
} catch (Exception $e) {
    echo "Error injecting quote: " . $e->getMessage() . "\n";
}
?>
PHPEOF

# Execute injection script in the container
docker cp /tmp/inject_quote.php vtiger-app:/tmp/inject_quote.php
docker exec vtiger-app php /tmp/inject_quote.php

# Get initial quote count
INITIAL_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='Quotes' AND deleted=0")
echo "$INITIAL_COUNT" > /tmp/initial_quote_count.txt

# Ensure browser is logged in and navigate to Quotes module
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Quotes&view=List"
sleep 4

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Duplicate quote 'Q3 Hardware Refresh', discount 10%, change stage to Reviewed."