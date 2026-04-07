#!/bin/bash
echo "=== Setting up log_equipment_breakdown_ticket task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Seed the required data via PHP to ensure correct CRM entity relations
cat > /tmp/seed_asset_ticket_data.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once('includes/main/WebUI.php');
require_once('modules/Accounts/Accounts.php');
require_once('modules/Products/Products.php');
require_once('modules/Assets/Assets.php');

$current_user = Users::getActiveAdminUser();

// Create Organization if it doesn't exist
global $adb;
$org_id = 0;
$res = $adb->pquery("SELECT accountid FROM vtiger_account WHERE accountname=?", array('Memorial Healthcare System'));
if ($adb->num_rows($res) > 0) {
    $org_id = $adb->query_result($res, 0, 'accountid');
} else {
    $org = new Accounts();
    $org->column_fields['accountname'] = 'Memorial Healthcare System';
    $org->column_fields['assigned_user_id'] = $current_user->id;
    $org->save('Accounts');
    $org_id = $org->id;
}

// Create Product if it doesn't exist
$prod_id = 0;
$res = $adb->pquery("SELECT productid FROM vtiger_products WHERE productname=?", array('Sonosite Edge II Ultrasound'));
if ($adb->num_rows($res) > 0) {
    $prod_id = $adb->query_result($res, 0, 'productid');
} else {
    $prod = new Products();
    $prod->column_fields['productname'] = 'Sonosite Edge II Ultrasound';
    $prod->column_fields['discontinued'] = 1; // Active
    $prod->column_fields['assigned_user_id'] = $current_user->id;
    $prod->save('Products');
    $prod_id = $prod->id;
}

// Clean up any existing ticket that might interfere
$res = $adb->pquery("SELECT ticketid FROM vtiger_troubletickets WHERE title=?", array('Dead Transducer Probe'));
while ($row = $adb->fetch_array($res)) {
    $tid = $row['ticketid'];
    $adb->pquery("DELETE FROM vtiger_crmentity WHERE crmid=?", array($tid));
    $adb->pquery("DELETE FROM vtiger_troubletickets WHERE ticketid=?", array($tid));
}

// Ensure Asset exists and is 'In Service'
$asset_id = 0;
$res = $adb->pquery("SELECT assetsid FROM vtiger_assets WHERE serialnumber=?", array('SN-US-2024-9981'));
if ($adb->num_rows($res) > 0) {
    $asset_id = $adb->query_result($res, 0, 'assetsid');
    $adb->pquery("UPDATE vtiger_assets SET assetstatus='In Service', account=?, product=? WHERE assetsid=?", array($org_id, $prod_id, $asset_id));
    $adb->pquery("UPDATE vtiger_crmentity SET modifiedtime=NOW() WHERE crmid=?", array($asset_id));
} else {
    $asset = new Assets();
    $asset->column_fields['assetname'] = 'Sonosite Edge II - Radiology Dept';
    $asset->column_fields['serialnumber'] = 'SN-US-2024-9981';
    $asset->column_fields['assetstatus'] = 'In Service';
    $asset->column_fields['product'] = $prod_id;
    $asset->column_fields['account'] = $org_id;
    $asset->column_fields['assigned_user_id'] = $current_user->id;
    $asset->save('Assets');
    $asset_id = $asset->id;
}

echo "DATA SEEDED. ORG: $org_id, PROD: $prod_id, ASSET: $asset_id\n";
?>
PHPEOF

docker cp /tmp/seed_asset_ticket_data.php vtiger-app:/tmp/seed_asset_ticket_data.php
docker exec vtiger-app php /tmp/seed_asset_ticket_data.php 2>&1

# Get initial ticket count
INITIAL_TICKET_COUNT=$(get_ticket_count)
echo "Initial ticket count: $INITIAL_TICKET_COUNT"
echo "$INITIAL_TICKET_COUNT" > /tmp/initial_ticket_count.txt

# Login and navigate to dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== log_equipment_breakdown_ticket task setup complete ==="