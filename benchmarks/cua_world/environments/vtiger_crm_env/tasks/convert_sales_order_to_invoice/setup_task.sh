#!/bin/bash
echo "=== Setting up convert_sales_order_to_invoice task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Prepare PHP script to safely seed the prerequisite Sales Order via Vtiger API
cat > /tmp/setup_so.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';
require_once 'include/utils/utils.php';
vimport('includes.runtime.EntryPoint');

$user = Users::getActiveAdminUser();
vglobal('current_user', $user);

try {
    global $adb;
    // Clean up any existing conflicting records
    $adb->pquery("DELETE FROM vtiger_crmentity WHERE label IN ('Alpha Industries', 'SO-2026-Alpha', 'INV-2026-Alpha')", array());

    // Create Organization
    $account = Vtiger_Record_Model::getCleanInstance('Accounts');
    $account->set('accountname', 'Alpha Industries');
    $account->set('mode', '');
    $account->save();
    $accountId = $account->getId();

    // Create Products
    $p1 = Vtiger_Record_Model::getCleanInstance('Products');
    $p1->set('productname', 'Ergonomic Chair');
    $p1->set('unit_price', 150);
    $p1->set('qtyinstock', 100);
    $p1->set('mode', '');
    $p1->save();
    $p1Id = $p1->getId();

    $p2 = Vtiger_Record_Model::getCleanInstance('Products');
    $p2->set('productname', 'Conference Table');
    $p2->set('unit_price', 400);
    $p2->set('qtyinstock', 10);
    $p2->set('mode', '');
    $p2->save();
    $p2Id = $p2->getId();

    // Create Sales Order
    $so = Vtiger_Record_Model::getCleanInstance('SalesOrder');
    $so->set('subject', 'SO-2026-Alpha');
    $so->set('account_id', $accountId);
    $so->set('sostatus', 'Approved');
    $so->set('mode', '');
    $so->save();
    $soId = $so->getId();

    // Insert line items directly to bypass complex request payload generation
    $adb->pquery("INSERT INTO vtiger_inventoryproductrel (id, productid, sequence_no, quantity, listprice) VALUES (?, ?, ?, ?, ?)", array($soId, $p1Id, 1, 10, 150.00));
    $adb->pquery("INSERT INTO vtiger_inventoryproductrel (id, productid, sequence_no, quantity, listprice) VALUES (?, ?, ?, ?, ?)", array($soId, $p2Id, 2, 2, 400.00));

    // Update totals manually since we bypassed the UI logic for items
    $adb->pquery("UPDATE vtiger_salesorder SET total=?, subtotal=? WHERE salesorderid=?", array(2300.00, 2300.00, $soId));

    echo "SO_ID=" . $soId . "\nORG_ID=" . $accountId . "\nSUCCESS";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
?>
PHPEOF

# 3. Execute script inside Vtiger application container
echo "Seeding prerequisite records..."
docker cp /tmp/setup_so.php vtiger-app:/tmp/setup_so.php
PHP_OUTPUT=$(docker exec vtiger-app php /tmp/setup_so.php)
echo "$PHP_OUTPUT"

# Extract IDs to cross-reference later
SO_ID=$(echo "$PHP_OUTPUT" | grep "SO_ID=" | cut -d'=' -f2)
ORG_ID=$(echo "$PHP_OUTPUT" | grep "ORG_ID=" | cut -d'=' -f2)

if [ -z "$SO_ID" ]; then
    echo "ERROR: Failed to create prerequisite Sales Order."
    exit 1
fi

echo "$SO_ID" > /tmp/prereq_so_id.txt
echo "$ORG_ID" > /tmp/prereq_org_id.txt

# 4. Ensure logged in and navigate to Sales Orders list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=SalesOrder&view=List"
sleep 4

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== convert_sales_order_to_invoice task setup complete ==="
echo "Task: Convert SO-2026-Alpha to Invoice and add $50 shipping charge"