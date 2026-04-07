#!/bin/bash
echo "=== Setting up create_pricebook_products task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Record initial price book count
INITIAL_PB_COUNT=$(vtiger_count "vtiger_pricebook")
echo "Initial price book count: $INITIAL_PB_COUNT"
echo "$INITIAL_PB_COUNT" > /tmp/initial_pb_count.txt
chmod 666 /tmp/initial_pb_count.txt 2>/dev/null || true

# Verify the target price book does not already exist
EXISTING_PB=$(vtiger_db_query "SELECT pricebookid FROM vtiger_pricebook WHERE bookname='Premium Partner Pricing Q1 2025' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_PB" ]; then
    echo "WARNING: Price book already exists, removing"
    vtiger_db_query "DELETE FROM vtiger_pricebookproductrel WHERE pricebookid=$EXISTING_PB"
    vtiger_db_query "DELETE FROM vtiger_pricebook WHERE pricebookid=$EXISTING_PB"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_PB"
fi

# Ensure the 3 products exist via PHP script to properly create Vtiger entities
cat > /tmp/create_products.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
chdir('/var/www/html/vtigercrm');
require_once('vendor/autoload.php');
include_once('config.inc.php');
include_once('includes/main/WebUI.php');

$currentUser = Users::getActiveAdminUser();
\vglobal('current_user', $currentUser);

$products_to_create = [
    [
        'productname' => 'Wireless Bluetooth Headset',
        'unit_price' => '79.99',
        'productcategory' => 'Hardware',
        'manufacturer' => 'Sony',
        'discontinued' => '1',
        'description' => 'High quality wireless headset'
    ],
    [
        'productname' => 'USB-C Docking Station',
        'unit_price' => '149.99',
        'productcategory' => 'Hardware',
        'manufacturer' => 'Dell',
        'discontinued' => '1',
        'description' => 'Universal docking station'
    ],
    [
        'productname' => 'Ergonomic Keyboard Pro',
        'unit_price' => '129.99',
        'productcategory' => 'Hardware',
        'manufacturer' => 'Logitech',
        'discontinued' => '1',
        'description' => 'Ergonomic mechanical keyboard'
    ]
];

foreach ($products_to_create as $prodData) {
    $adb = PearDatabase::getInstance();
    $result = $adb->pquery("SELECT productid FROM vtiger_products WHERE productname=?", array($prodData['productname']));
    if ($adb->num_rows($result) == 0) {
        $recordModel = Vtiger_Record_Model::getCleanInstance('Products');
        foreach ($prodData as $key => $value) {
            $recordModel->set($key, $value);
        }
        $recordModel->save();
        echo "Created product: " . $prodData['productname'] . "\n";
    } else {
        echo "Product exists: " . $prodData['productname'] . "\n";
    }
}
?>
PHPEOF

echo "Checking/creating required products..."
docker cp /tmp/create_products.php vtiger-app:/tmp/create_products.php
docker exec vtiger-app php /tmp/create_products.php

# Ensure logged in and navigate to Home page
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== setup complete ==="