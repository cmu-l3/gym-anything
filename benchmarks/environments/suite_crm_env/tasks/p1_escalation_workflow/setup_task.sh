#!/bin/bash
set -e
echo "=== Setting up p1_escalation_workflow task ==="

source /workspace/scripts/task_utils.sh

# 0. Record timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Record baseline
echo "--- Recording baseline ---"
suitecrm_db_query "SELECT id, name, status, priority, date_entered FROM cases WHERE deleted=0 ORDER BY name" > /tmp/p1e_baseline.txt
chmod 666 /tmp/p1e_baseline.txt

# 2. Create stale P1 cases and modify existing cases via PHP
cat > /tmp/p1e_seed.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html');
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

$att_id   = $db->getOne("SELECT id FROM accounts WHERE name='AT&T Inc.' AND deleted=0");
$gs_id    = $db->getOne("SELECT id FROM accounts WHERE name='Goldman Sachs Group Inc.' AND deleted=0");
$tesla_id = $db->getOne("SELECT id FROM accounts WHERE name='Tesla Inc.' AND deleted=0");
$cisco_id = $db->getOne("SELECT id FROM accounts WHERE name='Cisco Systems Inc.' AND deleted=0");
$adobe_id = $db->getOne("SELECT id FROM accounts WHERE name='Adobe Inc.' AND deleted=0");

// --- 3 stale P1 cases (>7 days old, Open_New status) ---
$stale_cases = [
    [
        'name'        => 'Critical outage: East Coast data center cluster offline',
        'status'      => 'Open_New',
        'priority'    => 'P1',
        'type'        => 'Product',
        'account_id'  => $att_id,
        'description' => 'Complete loss of connectivity to East Coast data center cluster affecting all enterprise customers in the NY/NJ/CT region. Redundant links have also failed. Estimated 12,000 business customers without service. Network operations center has been unable to restore connectivity via standard failover procedures.',
        'days_old'    => 14,
    ],
    [
        'name'        => 'Complete system failure during market hours',
        'status'      => 'Open_New',
        'priority'    => 'P1',
        'type'        => 'Product',
        'account_id'  => $gs_id,
        'description' => 'Trading platform experienced complete system failure at 10:47 AM EST during peak market hours. All 2,400 traders on the floor lost access to order management systems. Backup systems failed to activate within the 30-second SLA window. Estimated revenue impact exceeds $5M per hour.',
        'days_old'    => 10,
    ],
    [
        'name'        => 'Production line emergency halt - sensor array malfunction',
        'status'      => 'Open_Assigned',
        'priority'    => 'P1',
        'type'        => 'Product',
        'account_id'  => $tesla_id,
        'description' => 'Gigafactory production line 4 emergency stopped after sensor array reported anomalous temperature readings. 850 workers evacuated per safety protocol. Quality control sensors on 3 adjacent lines also showing intermittent failures. Production halted across 4 lines until sensor calibration is verified.',
        'days_old'    => 8,
    ],
];

foreach ($stale_cases as $sc) {
    $days = $sc['days_old'];
    unset($sc['days_old']);
    $bean = BeanFactory::newBean('Cases');
    foreach ($sc as $k => $v) { $bean->$k = $v; }
    $bean->save();
    // Backdate the date_entered
    $past_date = date('Y-m-d H:i:s', strtotime("-{$days} days"));
    $db->query("UPDATE cases SET date_entered='{$past_date}', date_modified='{$past_date}' WHERE id='{$bean->id}'");
    echo "STALE_P1:" . $bean->id . ":" . $sc['name'] . "\n";
}

// --- P2 case that should be P1 (>500 users affected) ---
$bean = BeanFactory::newBean('Cases');
$bean->name        = 'Network monitoring alert storm - 650 retail locations offline';
$bean->status      = 'Open_New';
$bean->priority    = 'P2';
$bean->type        = 'Product';
$bean->account_id  = $cisco_id;
$bean->description = 'Monitoring system generating cascading alerts from 650 retail store locations. Network switches at affected locations are showing packet loss rates of 40-60%. Point-of-sale systems at all 650 locations are non-functional. Store managers are reporting complete loss of card payment processing capability. Approximately 3,200 employees are unable to process transactions.';
$bean->save();
echo "UNDERCLASS:" . $bean->id . ":Network monitoring alert storm\n";

// --- Contamination: P2 case that should NOT be upgraded (only 3 users) ---
$bean2 = BeanFactory::newBean('Cases');
$bean2->name        = 'PDF export font rendering issue for 3 internal users';
$bean2->status      = 'Open_Assigned';
$bean2->priority    = 'P2';
$bean2->type        = 'Product';
$bean2->account_id  = $adobe_id;
$bean2->description = 'Three users in the marketing department report that PDF exports from the dashboard show incorrect font rendering. Impact limited to 3 internal users generating monthly reports. Workaround available: export as PNG and convert.';
$bean2->save();
echo "CONTAM:" . $bean2->id . ":PDF export font rendering issue\n";
?>
PHPEOF

docker cp /tmp/p1e_seed.php suitecrm-app:/tmp/p1e_seed.php
PHP_OUT=$(docker exec suitecrm-app php /tmp/p1e_seed.php 2>&1)
echo "$PHP_OUT"

# Save IDs
echo "$PHP_OUT" | grep '^STALE_P1:' | cut -d: -f2 > /tmp/p1e_stale_ids.txt
echo "$PHP_OUT" | grep '^UNDERCLASS:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/p1e_underclass_id.txt
echo "$PHP_OUT" | grep '^CONTAM:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/p1e_contam_id.txt
chmod 666 /tmp/p1e_*.txt

# 3. Modify existing Walmart case description to indicate >500 user impact
WALMART_CASE_ID=$(suitecrm_db_query "SELECT id FROM cases WHERE name='Custom report query timeout on large datasets' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
echo "$WALMART_CASE_ID" > /tmp/p1e_walmart_id.txt
chmod 666 /tmp/p1e_walmart_id.txt

suitecrm_db_query "UPDATE cases SET description='Custom reports with date ranges exceeding 90 days are timing out at the 30-second mark. Dataset contains 2.3M transaction records across all store locations. This is now affecting 2,100 store managers across all US regions who rely on these reports for daily inventory decisions and reorder workflows. Multiple regional directors have escalated requesting immediate resolution. Need query optimization or configurable timeout.' WHERE id='${WALMART_CASE_ID}'"
echo "Updated Walmart case description to indicate 2100 users affected"

# 4. Also get existing seed P1 Open_New case IDs for tracking
suitecrm_db_query "SELECT id FROM cases WHERE priority='P1' AND status='Open_New' AND deleted=0" > /tmp/p1e_all_p1_open_new.txt
chmod 666 /tmp/p1e_all_p1_open_new.txt

# 5. Ensure logged in and navigate to Cases
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Cases&action=index"
sleep 3

take_screenshot /tmp/p1e_initial.png

echo "=== p1_escalation_workflow setup complete ==="
echo "3 stale P1 cases (>7 days), 1 underclassified P2 (Cisco), 1 modified P2 (Walmart), 1 contamination P2 (Adobe)"
