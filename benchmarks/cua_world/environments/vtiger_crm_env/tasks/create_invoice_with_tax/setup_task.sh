#!/bin/bash
echo "=== Setting up create_invoice_with_tax task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean any existing invoice with the target subject to prevent collisions
EXISTING=$(vtiger_db_query "SELECT invoiceid FROM vtiger_invoice WHERE subject='INV-2024-GREENFIELD' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Target invoice already exists, removing..."
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_invoice WHERE invoiceid=$EXISTING"
fi

# 2. Record initial invoice count
INITIAL_INVOICE_COUNT=$(vtiger_count "vtiger_invoice" "1=1")
echo "$INITIAL_INVOICE_COUNT" > /tmp/initial_invoice_count.txt
echo "Initial invoice count: $INITIAL_INVOICE_COUNT"

# 3. Create prerequisite records using Vtiger's native PHP framework
cat > /tmp/create_prereqs.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';
require_once 'modules/Users/Users.php';
vimport('includes.runtime.EntryPoint');

$user = Users::getActiveAdminUser();
\vglobal('current_user', $user);

// Update Sales Tax to 8.250%
global $adb;
$adb->pquery("UPDATE vtiger_inventorytaxinfo SET taxlabel='Sales Tax', percentage='8.250', deleted=0 WHERE taxname='tax1'", array());

// Create Organization
$org = Vtiger_Record_Model::getCleanInstance('Accounts');
$org->set('accountname', 'Greenfield Landscaping LLC');
$org->set('assigned_user_id', $user->id);
$org->save();
$org_id = $org->getId();

// Create Contact
$contact = Vtiger_Record_Model::getCleanInstance('Contacts');
$contact->set('firstname', 'Maria');
$contact->set('lastname', 'Gonzalez');
$contact->set('account_id', $org_id);
$contact->set('assigned_user_id', $user->id);
$contact->save();

// Create Product 1
$p1 = Vtiger_Record_Model::getCleanInstance('Products');
$p1->set('productname', 'Commercial Lawn Mower');
$p1->set('unit_price', 1250.00);
$p1->set('assigned_user_id', $user->id);
$p1->save();

// Create Product 2
$p2 = Vtiger_Record_Model::getCleanInstance('Products');
$p2->set('productname', 'Irrigation Control System');
$p2->set('unit_price', 340.00);
$p2->set('assigned_user_id', $user->id);
$p2->save();

echo "Prerequisites created successfully.\n";
PHPEOF

docker cp /tmp/create_prereqs.php vtiger-app:/tmp/create_prereqs.php
docker exec vtiger-app php /tmp/create_prereqs.php

# 4. Ensure logged in and navigate to Invoices list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Invoice&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_invoice_initial.png

echo "=== create_invoice_with_tax task setup complete ==="