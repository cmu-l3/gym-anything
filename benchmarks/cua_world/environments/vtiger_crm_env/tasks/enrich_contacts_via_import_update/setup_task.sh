#!/bin/bash
echo "=== Setting up enrich_contacts_via_import_update task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the PHP seeder script to inject the 10 target contacts with OLD data
cat > /tmp/seed_enrichment.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once('includes/main/WebUI.php');
require_once('vendor/autoload.php');
vimport('includes.runtime.EntryPoint');

$adminUser = Users::getActiveAdminUser();
$adb = PearDatabase::getInstance();

$data = [
    ['firstname'=>'Michael', 'lastname'=>'Scott', 'email'=>'m.scott@example.com', 'title'=>'Sales', 'phone'=>'000-0000'],
    ['firstname'=>'Pam', 'lastname'=>'Beesly', 'email'=>'p.beesly@example.com', 'title'=>'Receptionist', 'phone'=>'000-0001'],
    ['firstname'=>'Jim', 'lastname'=>'Halpert', 'email'=>'j.halpert@example.com', 'title'=>'Sales', 'phone'=>'000-0002'],
    ['firstname'=>'Dwight', 'lastname'=>'Schrute', 'email'=>'d.schrute@example.com', 'title'=>'Sales', 'phone'=>'000-0003'],
    ['firstname'=>'Angela', 'lastname'=>'Martin', 'email'=>'a.martin@example.com', 'title'=>'Accounting', 'phone'=>'000-0004'],
    ['firstname'=>'Kevin', 'lastname'=>'Malone', 'email'=>'k.malone@example.com', 'title'=>'Accounting', 'phone'=>'000-0005'],
    ['firstname'=>'Oscar', 'lastname'=>'Martinez', 'email'=>'o.martinez@example.com', 'title'=>'Accounting', 'phone'=>'000-0006'],
    ['firstname'=>'Stanley', 'lastname'=>'Hudson', 'email'=>'s.hudson@example.com', 'title'=>'Sales', 'phone'=>'000-0007'],
    ['firstname'=>'Phyllis', 'lastname'=>'Lapin', 'email'=>'p.vance@example.com', 'title'=>'Sales', 'phone'=>'000-0008'],
    ['firstname'=>'Kelly', 'lastname'=>'Kapoor', 'email'=>'k.kapoor@example.com', 'title'=>'Support', 'phone'=>'000-0009']
];

foreach($data as $row) {
    // Check if exists
    $check = $adb->pquery("SELECT contactid FROM vtiger_contactdetails INNER JOIN vtiger_crmentity ON crmid=contactid WHERE email=? AND deleted=0", array($row['email']));
    if($adb->num_rows($check) == 0) {
        // Create new
        $record = Vtiger_Record_Model::getCleanInstance('Contacts');
        $record->set('firstname', $row['firstname']);
        $record->set('lastname', $row['lastname']);
        $record->set('email', $row['email']);
        $record->set('title', $row['title']);
        $record->set('phone', $row['phone']);
        $record->set('assigned_user_id', $adminUser->id);
        $record->save();
        $contactid = $record->getId();
    } else {
        // Reset existing back to old data to allow task retries
        $contactid = $adb->query_result($check, 0, 'contactid');
        $record = Vtiger_Record_Model::getInstanceById($contactid, 'Contacts');
        $record->set('title', $row['title']);
        $record->set('phone', $row['phone']);
        $record->save();
    }
    // Backdate modifiedtime by 1 day so we can reliably detect if the agent updated it
    $adb->pquery("UPDATE vtiger_crmentity SET modifiedtime = NOW() - INTERVAL 1 DAY WHERE crmid=?", array($contactid));
}
echo "Seed complete.\n";
PHPEOF

docker cp /tmp/seed_enrichment.php vtiger-app:/tmp/seed_enrichment.php
docker exec vtiger-app php /tmp/seed_enrichment.php

# 2. Record initial contact count for anti-gaming (must not increase!)
INITIAL_CONTACT_COUNT=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='Contacts' AND deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_CONTACT_COUNT" > /tmp/initial_contact_count.txt
chmod 666 /tmp/initial_contact_count.txt 2>/dev/null || true
echo "Initial contact count: $INITIAL_CONTACT_COUNT"

# 3. Create the CSV file the agent will use to import NEW data
cat > /home/ga/Documents/enriched_contacts.csv << 'CSVEOF'
First Name,Last Name,Email,Title,Direct Phone
Michael,Scott,m.scott@example.com,Regional Manager,570-555-1234
Pam,Beesly,p.beesly@example.com,Office Administrator,570-555-1235
Jim,Halpert,j.halpert@example.com,Co-Manager,570-555-1236
Dwight,Schrute,d.schrute@example.com,Assistant to the Regional Manager,570-555-1237
Angela,Martin,a.martin@example.com,Senior Accountant,570-555-1238
Kevin,Malone,k.malone@example.com,Accountant,570-555-1239
Oscar,Martinez,o.martinez@example.com,Chief Accountant,570-555-1240
Stanley,Hudson,s.hudson@example.com,Senior Sales Representative,570-555-1241
Phyllis,Lapin,p.vance@example.com,Senior Sales Representative,570-555-1242
Kelly,Kapoor,k.kapoor@example.com,Customer Service Director,570-555-1243
CSVEOF
chown ga:ga /home/ga/Documents/enriched_contacts.csv

# 4. Record task start time (Unix timestamp)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# 5. Ensure logged in and navigate to Contacts list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Contacts&view=List"
sleep 4

# 6. Take initial screenshot
take_screenshot /tmp/enrich_contacts_initial.png

echo "=== enrich_contacts_via_import_update task setup complete ==="