#!/bin/bash
set -e
echo "=== Setting up process_lost_deal_followup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Provide the Competitor Pricing PDF
mkdir -p /home/ga/Documents
# Try fetching a real lightweight PDF from W3C
curl -L -s -o /home/ga/Documents/competitor_pricing_apex.pdf "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf" || true
# Fallback to creating a valid local PDF if download failed
if [ ! -s /home/ga/Documents/competitor_pricing_apex.pdf ]; then
    echo "Fallback: Generating local PDF"
    convert -size 600x400 xc:white -font DejaVu-Sans -pointsize 24 -draw "text 50,50 'Competitor Pricing - Apex'" /home/ga/Documents/competitor_pricing_apex.pdf 2>/dev/null || \
    echo "Competitor pricing data" > /home/ga/Documents/competitor_pricing_apex.pdf
fi
chown ga:ga /home/ga/Documents/competitor_pricing_apex.pdf
chmod 644 /home/ga/Documents/competitor_pricing_apex.pdf

# 2. Seed the CRM with the target Organization and Potential cleanly via PHP API
cat > /tmp/create_setup_data.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';
vimport('includes.runtime.EntryPoint');
$current_user = Users::getActiveAdminUser();
$_SESSION['authenticated_user_id'] = $current_user->id;

global $adb;
// Only create if it doesn't already exist
$result = $adb->pquery("SELECT potentialid FROM vtiger_potential WHERE potentialname='Apex Corp - Q3 Hardware Restock'", array());

if($adb->num_rows($result) == 0) {
    // 1. Create Organization
    $accountRecord = Vtiger_Record_Model::getCleanInstance('Accounts');
    $accountRecord->set('accountname', 'Apex Corporation');
    $accountRecord->set('assigned_user_id', $current_user->id);
    $accountRecord->save();
    
    // 2. Create Potential linked to Organization
    $potentialRecord = Vtiger_Record_Model::getCleanInstance('Potentials');
    $potentialRecord->set('potentialname', 'Apex Corp - Q3 Hardware Restock');
    $potentialRecord->set('related_to', $accountRecord->getId());
    $potentialRecord->set('amount', '45000');
    $potentialRecord->set('sales_stage', 'Negotiation/Review');
    $potentialRecord->set('closingdate', '2026-03-01');
    $potentialRecord->set('assigned_user_id', $current_user->id);
    $potentialRecord->save();
    echo "Created Setup Data Successfully.\n";
} else {
    echo "Setup Data already exists.\n";
}
?>
PHPEOF

docker cp /tmp/create_setup_data.php vtiger-app:/tmp/create_setup_data.php
docker exec vtiger-app php /tmp/create_setup_data.php

# 3. Open Firefox, ensure logged in, and navigate to Potentials list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 3

# 4. Take initial screenshot as evidence of starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="