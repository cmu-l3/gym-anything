#!/bin/bash
echo "=== Setting up setup_recurring_sales_order task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# 2. Prepare database prerequisites via Vtiger API to ensure integrity
cat > /tmp/seed_task_prereqs.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
chdir('/var/www/html/vtigercrm');
require_once('includes/main/WebUI.php');
require_once('modules/Vtiger/models/Record.php');

$current_user = Users::getActiveAdminUser();
\vglobal('current_user', $current_user);

$db = PearDatabase::getInstance();

// Seed Organization
$result = $db->pquery("SELECT accountid FROM vtiger_account WHERE accountname = 'Global Trade Corp'", array());
if ($db->num_rows($result) == 0) {
    $orgRecord = Vtiger_Record_Model::getCleanInstance('Accounts');
    $orgRecord->set('accountname', 'Global Trade Corp');
    $orgRecord->set('bill_street', '100 Global Way');
    $orgRecord->set('bill_city', 'New York');
    $orgRecord->set('bill_state', 'NY');
    $orgRecord->set('bill_country', 'USA');
    $orgRecord->set('assigned_user_id', $current_user->id);
    $orgRecord->save();
    echo "Created Org: Global Trade Corp\n";
}

// Seed Service
$result = $db->pquery("SELECT serviceid FROM vtiger_service WHERE servicename = 'Enterprise Printer Lease & Maintenance'", array());
if ($db->num_rows($result) == 0) {
    $serviceRecord = Vtiger_Record_Model::getCleanInstance('Services');
    $serviceRecord->set('servicename', 'Enterprise Printer Lease & Maintenance');
    $serviceRecord->set('unit_price', '450.00');
    $serviceRecord->set('assigned_user_id', $current_user->id);
    $serviceRecord->save();
    echo "Created Service: Enterprise Printer Lease & Maintenance\n";
}
?>
PHPEOF

docker cp /tmp/seed_task_prereqs.php vtiger-app:/tmp/seed_task_prereqs.php
docker exec vtiger-app php /tmp/seed_task_prereqs.php

# 3. Clean up any existing Sales Orders that match our target subject (Anti-Gaming)
vtiger_db_query "UPDATE vtiger_crmentity JOIN vtiger_salesorder ON vtiger_crmentity.crmid = vtiger_salesorder.salesorderid SET vtiger_crmentity.deleted=1 WHERE vtiger_salesorder.subject='2025 Printer Lease Contract - Global Trade Corp'"

# 4. Ensure logged in and navigate to Sales Orders list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=SalesOrder&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/setup_recurring_sales_order_initial.png

echo "=== setup_recurring_sales_order task setup complete ==="
echo "Task: Setup Recurring Sales Order for Managed Services"