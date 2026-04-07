#!/bin/bash
echo "=== Setting up create_product_bundle task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Boot up Vtiger and ensure the 3 child products exist via internal PHP script
cat > /tmp/seed_bundle_products.php << 'PHPEOF'
<?php
error_reporting(E_ERROR);
chdir('/var/www/html/vtigercrm');
require_once('includes/main/WebUI.php');
vimport('includes.runtime.BaseModel');

$current_user = Users::getActiveAdminUser();
$products = ['Smart Hub Pro', 'RGB Smart Bulb', 'WiFi Smart Plug'];

$db = PearDatabase::getInstance();
foreach($products as $pname) {
    $res = $db->pquery("SELECT productid FROM vtiger_products INNER JOIN vtiger_crmentity ON crmid=productid WHERE deleted=0 AND productname=?", array($pname));
    if($db->num_rows($res) == 0) {
        $record = Vtiger_Record_Model::getCleanInstance('Products');
        $record->set('productname', $pname);
        $record->set('product_no', 'PRD-'.rand(10000,99999));
        $record->set('unit_price', 29.99);
        $record->set('qtyinstock', 100);
        $record->set('assigned_user_id', $current_user->id);
        $record->save();
        echo "Created $pname\n";
    } else {
        echo "Exists $pname\n";
    }
}
?>
PHPEOF

docker cp /tmp/seed_bundle_products.php vtiger-app:/tmp/seed_bundle_products.php
docker exec vtiger-app php /tmp/seed_bundle_products.php

# 2. Verify target bundle does not already exist (clean state)
EXISTING=$(vtiger_db_query "SELECT productid FROM vtiger_products INNER JOIN vtiger_crmentity ON crmid=productid WHERE productname='Smart Home Starter Kit' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Product Bundle already exists, marking as deleted"
    vtiger_db_query "UPDATE vtiger_crmentity SET deleted=1 WHERE crmid=$EXISTING"
fi

# 3. Record initial product count
INITIAL_PRODUCT_COUNT=$(vtiger_count "vtiger_products p INNER JOIN vtiger_crmentity c ON c.crmid=p.productid" "c.deleted=0")
echo "Initial product count: $INITIAL_PRODUCT_COUNT"
rm -f /tmp/initial_product_count.txt 2>/dev/null || true
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt
chmod 666 /tmp/initial_product_count.txt 2>/dev/null || true

# 4. Ensure logged in and navigate to Products list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Products&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_bundle_initial.png

echo "=== create_product_bundle task setup complete ==="