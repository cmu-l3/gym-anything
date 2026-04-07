#!/bin/bash
echo "=== Setting up create_purchase_order task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial PO count for anti-gaming verification
INITIAL_PO_COUNT=$(vtiger_count "vtiger_purchaseorder" "1=1")
echo "$INITIAL_PO_COUNT" > /tmp/initial_po_count.txt
echo "Initial PO count: $INITIAL_PO_COUNT"

# Delete any existing PO with our target subject to ensure clean slate
EXISTING_PO=$(vtiger_db_query "SELECT purchaseorderid FROM vtiger_purchaseorder WHERE subject='Spring 2025 Landscaping Materials' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_PO" ] && [ "$EXISTING_PO" != "NULL" ]; then
    echo "Cleaning up existing PO..."
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_PO"
    vtiger_db_query "DELETE FROM vtiger_purchaseorder WHERE purchaseorderid=$EXISTING_PO"
    vtiger_db_query "DELETE FROM vtiger_inventoryproductrel WHERE id=$EXISTING_PO"
fi

# Create prerequisite vendor and products via PHP script
cat > /tmp/create_po_prerequisites.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html/vtigercrm');
require_once('config.inc.php');
include_once('include/database/PearDatabase.php');

$adb = PearDatabase::getInstance();
$adb->connect();
$now = date('Y-m-d H:i:s');

function getNextId($adb) {
    $r = $adb->pquery("SELECT MAX(crmid) AS m FROM vtiger_crmentity", []);
    return (int)$adb->query_result($r, 0, 'm') + 1;
}

// Create Vendor if not exists
$r = $adb->pquery("SELECT vendorid FROM vtiger_vendor WHERE vendorname=?", ['SunBelt Outdoor Supply']);
if ($adb->num_rows($r) == 0) {
    $vid = getNextId($adb);
    $adb->pquery("INSERT INTO vtiger_crmentity (crmid,smcreatorid,smownerid,setype,createdtime,modifiedtime,presence,deleted,label) VALUES (?,1,1,'Vendors',?,?,1,0,?)", 
        [$vid,$now,$now,'SunBelt Outdoor Supply']);
    $adb->pquery("INSERT INTO vtiger_vendor (vendorid,vendorname,phone,email,website,city,state,country,postalcode) VALUES (?,'SunBelt Outdoor Supply','512-555-0187','orders@sunbeltoutdoor.com','www.sunbeltoutdoor.com','Austin','TX','United States','78701')", 
        [$vid]);
    // Insert custom fields row (required for edit views)
    $adb->pquery("INSERT IGNORE INTO vtiger_vendorcf (vendorid) VALUES (?)", [$vid]);
    echo "Created vendor ID=$vid\n";
} else {
    echo "Vendor 'SunBelt Outdoor Supply' already exists\n";
}

// Create Products
$products = [
    ['Commercial Fertilizer 50lb Bag', 38.50, 'FERT-50LB'],
    ['Bermuda Grass Seed 25lb', 52.00, 'SEED-BG25'],
    ['Drip Irrigation Kit', 125.00, 'IRR-DRIP01'],
];
foreach ($products as $p) {
    $r = $adb->pquery("SELECT productid FROM vtiger_products WHERE productname=?", [$p[0]]);
    if ($adb->num_rows($r) == 0) {
        $pid = getNextId($adb);
        $adb->pquery("INSERT INTO vtiger_crmentity (crmid,smcreatorid,smownerid,setype,createdtime,modifiedtime,presence,deleted,label) VALUES (?,1,1,'Products',?,?,1,0,?)", 
            [$pid,$now,$now,$p[0]]);
        $adb->pquery("INSERT INTO vtiger_products (productid,productname,unit_price,product_no,discontinued) VALUES (?,?,?,?,0)", 
            [$pid,$p[0],$p[1],$p[2]]);
        $adb->pquery("INSERT IGNORE INTO vtiger_productcf (productid) VALUES (?)", [$pid]);
        echo "Created product '{$p[0]}' ID=$pid\n";
    } else {
        echo "Product '{$p[0]}' already exists\n";
    }
}
echo "DONE\n";
?>
PHPEOF

docker cp /tmp/create_po_prerequisites.php vtiger-app:/tmp/create_po_prerequisites.php
docker exec vtiger-app php /tmp/create_po_prerequisites.php 2>&1

# Verify prerequisites were created
VENDOR_CHECK=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_vendor WHERE vendorname='SunBelt Outdoor Supply'" | tr -d '[:space:]')
echo "Vendor check: $VENDOR_CHECK (expect 1)"

# Log in to Vtiger and navigate to dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Purchase Order task setup complete ==="