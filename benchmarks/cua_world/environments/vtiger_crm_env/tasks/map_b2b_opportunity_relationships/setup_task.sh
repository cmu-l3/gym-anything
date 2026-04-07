#!/bin/bash
echo "=== Setting up map_b2b_opportunity_relationships task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

echo "Cleaning up any existing target records to ensure fresh state..."
# Use direct SQL queries to clean up matching test records so we can recreate them cleanly
vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid IN (SELECT contactid FROM vtiger_contactdetails WHERE (firstname='Marcus' AND lastname='Oyelaran') OR (firstname='Priya' AND lastname='Chakraborty'));"
vtiger_db_query "DELETE FROM vtiger_contactdetails WHERE (firstname='Marcus' AND lastname='Oyelaran') OR (firstname='Priya' AND lastname='Chakraborty');"

vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid IN (SELECT potentialid FROM vtiger_potential WHERE potentialname='Cloud Migration Phase 2');"
vtiger_db_query "DELETE FROM vtiger_potential WHERE potentialname='Cloud Migration Phase 2';"

vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid IN (SELECT notesid FROM vtiger_notes WHERE title='Cloud Security Addendum');"
vtiger_db_query "DELETE FROM vtiger_notes WHERE title='Cloud Security Addendum';"

vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid IN (SELECT productid FROM vtiger_products WHERE productname='Enterprise Cloud Server');"
vtiger_db_query "DELETE FROM vtiger_products WHERE productname='Enterprise Cloud Server';"

echo "Injecting clean requisite records via Vtiger PHP framework..."
cat > /tmp/create_b2b_records.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once('includes/main/WebUI.php');
vimport('includes.runtime.BaseModel');
vimport('includes.runtime.Globals');
$user = Users::getActiveAdminUser();
vglobal('current_user', $user);

// Create Opportunity (Potential)
$opp = Vtiger_Record_Model::getCleanInstance('Potentials');
$opp->set('potentialname', 'Cloud Migration Phase 2');
$opp->set('assigned_user_id', $user->id);
$opp->set('closingdate', '2026-12-31');
$opp->set('sales_stage', 'Prospecting');
$opp->save();

// Create Contact 1
$c1 = Vtiger_Record_Model::getCleanInstance('Contacts');
$c1->set('firstname', 'Marcus');
$c1->set('lastname', 'Oyelaran');
$c1->set('assigned_user_id', $user->id);
$c1->save();

// Create Contact 2
$c2 = Vtiger_Record_Model::getCleanInstance('Contacts');
$c2->set('firstname', 'Priya');
$c2->set('lastname', 'Chakraborty');
$c2->set('assigned_user_id', $user->id);
$c2->save();

// Create Document
$doc = Vtiger_Record_Model::getCleanInstance('Documents');
$doc->set('notes_title', 'Cloud Security Addendum');
$doc->set('assigned_user_id', $user->id);
$doc->set('filelocationtype', 'I');
$doc->set('filestatus', '1');
$doc->save();

// Create Product
$prod = Vtiger_Record_Model::getCleanInstance('Products');
$prod->set('productname', 'Enterprise Cloud Server');
$prod->set('assigned_user_id', $user->id);
$prod->save();

echo "Records successfully created.";
?>
PHPEOF

docker cp /tmp/create_b2b_records.php vtiger-app:/tmp/create_b2b_records.php
docker exec vtiger-app php /tmp/create_b2b_records.php 2>&1

# Ensure logged in and navigate to Opportunities (Potentials) list
echo "Logging in and navigating to Potentials module..."
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 4

# Take initial screenshot
take_screenshot /tmp/map_b2b_opportunity_initial.png

echo "=== map_b2b_opportunity_relationships task setup complete ==="