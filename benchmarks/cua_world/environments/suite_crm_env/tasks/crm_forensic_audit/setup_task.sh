#!/bin/bash
set -e
echo "=== Setting up crm_forensic_audit task ==="

source /workspace/scripts/task_utils.sh

# 0. Clean up any data from previous runs
echo "--- Cleaning up previous run data ---"
suitecrm_db_query "UPDATE accounts SET deleted=1 WHERE name IN ('Pinnacle Defense Systems', 'Quantum Dynamics Inc', 'Evergreen Health Partners') AND deleted=0" 2>/dev/null || true
suitecrm_db_query "UPDATE opportunities SET deleted=1 WHERE name LIKE 'Pinnacle -%' OR name LIKE 'Quantum -%' OR name LIKE 'Evergreen -%'" 2>/dev/null || true
suitecrm_db_query "UPDATE contacts SET deleted=1 WHERE (first_name='Nikolai' AND last_name='Volkov') OR (first_name='Elena' AND last_name='Vasquez') OR (first_name='Diana' AND last_name='Morales') OR (first_name='Takeshi' AND last_name='Nakamura') OR (first_name='Sarah' AND last_name='Mitchell')" 2>/dev/null || true
suitecrm_db_query "UPDATE users SET deleted=1, status='Inactive' WHERE user_name='aturner'" 2>/dev/null || true

# 1. Record timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 2. Record baseline
echo "--- Recording baseline ---"
suitecrm_db_query "SELECT id, name, amount, sales_stage FROM opportunities WHERE deleted=0 ORDER BY name" > /tmp/cfa_baseline_opps.txt
suitecrm_db_query "SELECT c.id, c.first_name, c.last_name FROM contacts c WHERE c.deleted=0 ORDER BY c.last_name" > /tmp/cfa_baseline_contacts.txt
suitecrm_db_query "SELECT id, name, account_type FROM accounts WHERE deleted=0 ORDER BY name" > /tmp/cfa_baseline_accounts.txt
chmod 666 /tmp/cfa_baseline_*.txt

# 3. Create all data via PHP
cat > /tmp/cfa_seed.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html');
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

// Get Apple account ID (target for contact reassignment)
$apple_id = $db->getOne("SELECT id FROM accounts WHERE name='Apple Inc.' AND deleted=0");

// ========== 1. Create user Alex Turner ==========
$user = BeanFactory::newBean('Users');
$user->user_name = 'aturner';
$user->first_name = 'Alex';
$user->last_name = 'Turner';
$user->status = 'Active';
$user->employee_status = 'Active';
$user->is_admin = 0;
$user->user_hash = md5('TurnerPass2026!');
$user->save();
$turner_id = $user->id;
echo "USER:{$turner_id}\n";

// ========== 2. Create 3 accounts assigned to Turner ==========
$accounts_data = [
    [
        'name'            => 'Pinnacle Defense Systems',
        'industry'        => 'Defense',
        'account_type'    => 'Customer',
        'website'         => 'https://www.pinnacledefense.com',
        'phone_office'    => '(703) 555-0199',
        'billing_address_street' => '2400 Crystal Drive Suite 800',
        'billing_address_city'   => 'Arlington',
        'billing_address_state'  => 'VA',
        'billing_address_postalcode' => '22202',
        'billing_address_country'    => 'USA',
        'employees'       => '4200',
        'annual_revenue'  => '890000000',
        'description'     => 'Prime defense contractor specializing in radar systems, secure communications, and cybersecurity solutions for DoD and allied nations.',
    ],
    [
        'name'            => 'Quantum Dynamics Inc',
        'industry'        => 'Technology',
        'account_type'    => 'Customer',
        'website'         => 'https://www.quantumdyn.com',
        'phone_office'    => '(408) 555-0234',
        'billing_address_street' => '1 Quantum Plaza',
        'billing_address_city'   => 'San Jose',
        'billing_address_state'  => 'CA',
        'billing_address_postalcode' => '95113',
        'billing_address_country'    => 'USA',
        'employees'       => '1800',
        'annual_revenue'  => '420000000',
        'description'     => 'Enterprise software company focused on predictive maintenance, ML pipelines, and data warehouse solutions for manufacturing.',
    ],
    [
        'name'            => 'Evergreen Health Partners',
        'industry'        => 'Healthcare',
        'account_type'    => 'Customer',
        'website'         => 'https://www.evergreenhealth.org',
        'phone_office'    => '(312) 555-0178',
        'billing_address_street' => '500 N Michigan Ave Floor 32',
        'billing_address_city'   => 'Chicago',
        'billing_address_state'  => 'IL',
        'billing_address_postalcode' => '60611',
        'billing_address_country'    => 'USA',
        'employees'       => '6500',
        'annual_revenue'  => '1200000000',
        'description'     => 'Regional health system operating 12 hospitals and 45 outpatient clinics across the Midwest with a focus on telehealth innovation.',
    ],
];

$acct_ids = [];
foreach ($accounts_data as $ad) {
    $bean = BeanFactory::newBean('Accounts');
    foreach ($ad as $k => $v) { $bean->$k = $v; }
    $bean->assigned_user_id = $turner_id;
    $bean->save();
    $acct_ids[$ad['name']] = $bean->id;
    echo "ACCT:{$bean->id}:{$ad['name']}\n";
}

$pinnacle_id  = $acct_ids['Pinnacle Defense Systems'];
$quantum_id   = $acct_ids['Quantum Dynamics Inc'];
$evergreen_id = $acct_ids['Evergreen Health Partners'];

// ========== 3. RULE 1: Re-opened deals (2 to fix + 1 contamination) ==========

// Re-opened deal 1: description clearly says deal was lost
$r1a = BeanFactory::newBean('Opportunities');
$r1a->name             = 'Pinnacle - Radar Upgrade Contract';
$r1a->account_id       = $pinnacle_id;
$r1a->assigned_user_id = $turner_id;
$r1a->sales_stage      = 'Prospecting';
$r1a->probability      = 10;
$r1a->amount           = 2100000;
$r1a->date_closed      = '2026-08-15';
$r1a->lead_source      = 'Existing Customer';
$r1a->description      = 'Client declined our proposal after defense budget cuts in Q3 2025. They are no longer pursuing radar modernization for the current fiscal cycle.';
$r1a->save();
echo "REOPEN1:{$r1a->id}:Pinnacle - Radar Upgrade Contract\n";

// Re-opened deal 2: description says lost to competitor
$r1b = BeanFactory::newBean('Opportunities');
$r1b->name             = 'Quantum - ML Pipeline Accelerator';
$r1b->account_id       = $quantum_id;
$r1b->assigned_user_id = $turner_id;
$r1b->sales_stage      = 'Qualification';
$r1b->probability      = 20;
$r1b->amount           = 1400000;
$r1b->date_closed      = '2026-09-30';
$r1b->lead_source      = 'Trade Show';
$r1b->description      = 'Lost competitive evaluation to DataForge Systems in November 2025. Their platform was selected for the initial deployment phase.';
$r1b->save();
echo "REOPEN2:{$r1b->id}:Quantum - ML Pipeline Accelerator\n";

// Contamination: "declined" refers to COMPETITOR being declined, not our deal
$r1c = BeanFactory::newBean('Opportunities');
$r1c->name             = 'Evergreen - Patient Data Analytics Suite';
$r1c->account_id       = $evergreen_id;
$r1c->assigned_user_id = $turner_id;
$r1c->sales_stage      = 'Prospecting';
$r1c->probability      = 10;
$r1c->amount           = 3600000;
$r1c->date_closed      = '2026-10-31';
$r1c->lead_source      = 'Web Site';
$r1c->description      = "Evergreen's board declined the competing vendor's proposal due to HIPAA compliance gaps. Our solution passed their security review and we are now in active discussions with their CTO.";
$r1c->save();
echo "CONTAM_R1:{$r1c->id}:Evergreen - Patient Data Analytics Suite\n";

// ========== 4. RULE 2: Inflated amounts (2 to fix) ==========

// Inflated deal 1: $4,200,000 should be $2,100,000
$r2a = BeanFactory::newBean('Opportunities');
$r2a->name             = 'Quantum - Predictive Maintenance Platform';
$r2a->account_id       = $quantum_id;
$r2a->assigned_user_id = $turner_id;
$r2a->sales_stage      = 'Needs Analysis';
$r2a->probability      = 25;
$r2a->amount           = 4200000;
$r2a->date_closed      = '2026-11-30';
$r2a->lead_source      = 'Conference';
$r2a->description      = 'Approved procurement budget of $2,100,000 from VP Engineering. Phase 1 covers sensor integration across 3 manufacturing lines. Phase 2 (separate FY budget) would add predictive modeling capabilities.';
$r2a->save();
echo "INFLATE1:{$r2a->id}:Quantum - Predictive Maintenance Platform\n";

// Inflated deal 2: $5,800,000 should be $2,900,000
$r2b = BeanFactory::newBean('Opportunities');
$r2b->name             = 'Pinnacle - Cybersecurity Hardening Initiative';
$r2b->account_id       = $pinnacle_id;
$r2b->assigned_user_id = $turner_id;
$r2b->sales_stage      = 'Value Proposition';
$r2b->probability      = 30;
$r2b->amount           = 5800000;
$r2b->date_closed      = '2026-12-15';
$r2b->lead_source      = 'Partner';
$r2b->description      = 'Defense contract proposal submitted. Approved budget of $2,900,000 per the CPARS-reviewed SOW. Covers network penetration testing, zero-trust architecture design, and compliance certification.';
$r2b->save();
echo "INFLATE2:{$r2b->id}:Pinnacle - Cybersecurity Hardening Initiative\n";

// ========== 5. RULE 3: Fabricated + legitimate Closed Won ==========

// Fabricated: Closed Won with NO activity records
$r3a = BeanFactory::newBean('Opportunities');
$r3a->name             = 'Quantum - Enterprise Data Warehouse Migration';
$r3a->account_id       = $quantum_id;
$r3a->assigned_user_id = $turner_id;
$r3a->sales_stage      = 'Closed Won';
$r3a->probability      = 100;
$r3a->amount           = 3800000;
$r3a->date_closed      = '2026-02-10';
$r3a->lead_source      = 'Existing Customer';
$r3a->description      = 'Full data warehouse migration from on-prem Oracle to cloud-native Snowflake architecture. Includes ETL redesign and BI dashboard migration.';
$r3a->save();
echo "FABRICATED:{$r3a->id}:Quantum - Enterprise Data Warehouse Migration\n";

// Legitimate Closed Won 1: has Notes and Call
$r3b = BeanFactory::newBean('Opportunities');
$r3b->name             = 'Pinnacle - Secure Comms Platform';
$r3b->account_id       = $pinnacle_id;
$r3b->assigned_user_id = $turner_id;
$r3b->sales_stage      = 'Closed Won';
$r3b->probability      = 100;
$r3b->amount           = 1500000;
$r3b->date_closed      = '2025-11-30';
$r3b->lead_source      = 'Direct Mail';
$r3b->description      = 'Encrypted communications platform for classified operations. ITAR-compliant, deployed to 3 military installations.';
$r3b->save();
echo "LEGIT_CW1:{$r3b->id}:Pinnacle - Secure Comms Platform\n";

// Activity for legitimate CW1: Note
$note1 = BeanFactory::newBean('Notes');
$note1->name        = 'Contract executed - ITAR compliance verified';
$note1->parent_type = 'Opportunities';
$note1->parent_id   = $r3b->id;
$note1->description = 'Signed contract received from Pinnacle legal. ITAR compliance documentation attached and verified by our export control team.';
$note1->save();
echo "NOTE1:{$note1->id}\n";

// Activity for legitimate CW1: Call
$call1 = BeanFactory::newBean('Calls');
$call1->name        = 'Final negotiation with Pinnacle procurement';
$call1->status      = 'Held';
$call1->direction   = 'Outbound';
$call1->duration_hours   = 1;
$call1->duration_minutes = 0;
$call1->date_start  = date('Y-m-d H:i:s', strtotime('-120 days'));
$call1->date_end    = date('Y-m-d H:i:s', strtotime('-120 days +1 hour'));
$call1->parent_type = 'Opportunities';
$call1->parent_id   = $r3b->id;
$call1->description = 'Negotiated final pricing with Pinnacle procurement. Agreed on $1.5M for 3-year term.';
$call1->save();
echo "CALL1:{$call1->id}\n";

// Legitimate Closed Won 2: has Meeting and Note
$r3c = BeanFactory::newBean('Opportunities');
$r3c->name             = 'Evergreen - Telehealth Infrastructure';
$r3c->account_id       = $evergreen_id;
$r3c->assigned_user_id = $turner_id;
$r3c->sales_stage      = 'Closed Won';
$r3c->probability      = 100;
$r3c->amount           = 2200000;
$r3c->date_closed      = '2025-10-15';
$r3c->lead_source      = 'Conference';
$r3c->description      = 'Telehealth platform connecting 12 hospitals and 45 clinics. HIPAA-compliant video consultation and remote monitoring.';
$r3c->save();
echo "LEGIT_CW2:{$r3c->id}:Evergreen - Telehealth Infrastructure\n";

// Activity for legitimate CW2: Meeting
$meeting1 = BeanFactory::newBean('Meetings');
$meeting1->name        = 'Evergreen IT team - deployment kickoff';
$meeting1->status      = 'Held';
$meeting1->duration_hours   = 2;
$meeting1->duration_minutes = 0;
$meeting1->date_start  = date('Y-m-d H:i:s', strtotime('-150 days'));
$meeting1->date_end    = date('Y-m-d H:i:s', strtotime('-150 days +2 hours'));
$meeting1->parent_type = 'Opportunities';
$meeting1->parent_id   = $r3c->id;
$meeting1->location    = 'Evergreen Health HQ, Chicago';
$meeting1->description = 'Deployment kickoff with Evergreen IT leadership. Reviewed timeline, milestones, and resource allocation.';
$meeting1->save();
echo "MEETING1:{$meeting1->id}\n";

// Activity for legitimate CW2: Note
$note2 = BeanFactory::newBean('Notes');
$note2->name        = 'Implementation milestone 1 complete';
$note2->parent_type = 'Opportunities';
$note2->parent_id   = $r3c->id;
$note2->description = 'Phase 1 deployment complete: 4 hospitals connected to telehealth platform. Patient onboarding ahead of schedule.';
$note2->save();
echo "NOTE2:{$note2->id}\n";

// ========== 6. Legitimate active opportunities (should NOT be touched) ==========

$leg1 = BeanFactory::newBean('Opportunities');
$leg1->name             = 'Evergreen - EHR Integration Phase 2';
$leg1->account_id       = $evergreen_id;
$leg1->assigned_user_id = $turner_id;
$leg1->sales_stage      = 'Proposal/Price Quote';
$leg1->probability      = 65;
$leg1->amount           = 2800000;
$leg1->date_closed      = '2026-07-31';
$leg1->lead_source      = 'Existing Customer';
$leg1->description      = 'Follow-on engagement from successful Phase 1 deployment. Client requesting integration with 4 additional hospital systems and remote patient monitoring module.';
$leg1->save();
echo "LEGIT_ACTIVE1:{$leg1->id}:Evergreen - EHR Integration Phase 2\n";

$leg2 = BeanFactory::newBean('Opportunities');
$leg2->name             = 'Pinnacle - Training Simulation Platform';
$leg2->account_id       = $pinnacle_id;
$leg2->assigned_user_id = $turner_id;
$leg2->sales_stage      = 'Negotiation/Review';
$leg2->probability      = 80;
$leg2->amount           = 1900000;
$leg2->date_closed      = '2026-04-30';
$leg2->lead_source      = 'Direct Mail';
$leg2->description      = 'Final contract review with Pinnacle legal team. Expected signature by end of March 2026. VR-based training simulation for infantry and vehicle operators.';
$leg2->save();
echo "LEGIT_ACTIVE2:{$leg2->id}:Pinnacle - Training Simulation Platform\n";

// ========== 7. Contacts (3 to reassign + 2 contamination) ==========

// Misassigned contact 1: at Pinnacle but email domain is quantumdyn.com
$c1 = BeanFactory::newBean('Contacts');
$c1->first_name  = 'Nikolai';
$c1->last_name   = 'Volkov';
$c1->title       = 'Director of Engineering';
$c1->department  = 'R&D';
$c1->phone_work  = '(408) 555-0291';
$c1->email1      = 'n.volkov@quantumdyn.com';
$c1->account_id  = $pinnacle_id;
$c1->primary_address_city  = 'San Jose';
$c1->primary_address_state = 'CA';
$c1->description = 'Key technical contact for ML pipeline projects. Background in distributed systems.';
$c1->save();
echo "CONTACT_FIX1:{$c1->id}:Nikolai Volkov\n";

// Misassigned contact 2: at Quantum but email domain is evergreenhealth.org
$c2 = BeanFactory::newBean('Contacts');
$c2->first_name  = 'Elena';
$c2->last_name   = 'Vasquez';
$c2->title       = 'VP of Clinical Operations';
$c2->department  = 'Clinical Services';
$c2->phone_work  = '(312) 555-0347';
$c2->email1      = 'e.vasquez@evergreenhealth.org';
$c2->account_id  = $quantum_id;
$c2->primary_address_city  = 'Chicago';
$c2->primary_address_state = 'IL';
$c2->description = 'Primary decision maker for telehealth and clinical informatics initiatives.';
$c2->save();
echo "CONTACT_FIX2:{$c2->id}:Elena Vasquez\n";

// Misassigned contact 3: at Evergreen but email domain is apple.com
$c3 = BeanFactory::newBean('Contacts');
$c3->first_name  = 'Diana';
$c3->last_name   = 'Morales';
$c3->title       = 'Senior Product Manager';
$c3->department  = 'Product Development';
$c3->phone_work  = '(408) 996-1010';
$c3->email1      = 'd.morales@apple.com';
$c3->account_id  = $evergreen_id;
$c3->primary_address_city  = 'Cupertino';
$c3->primary_address_state = 'CA';
$c3->description = 'Manages enterprise integration products. Involved in health platform partnerships.';
$c3->save();
echo "CONTACT_FIX3:{$c3->id}:Diana Morales\n";

// Contamination contact 1: personal email (gmail.com) — should NOT be moved
$c4 = BeanFactory::newBean('Contacts');
$c4->first_name  = 'Takeshi';
$c4->last_name   = 'Nakamura';
$c4->title       = 'Consultant';
$c4->department  = 'External Advisory';
$c4->phone_work  = '(415) 555-0182';
$c4->email1      = 'takeshi.nakamura@gmail.com';
$c4->account_id  = $quantum_id;
$c4->primary_address_city  = 'San Francisco';
$c4->primary_address_state = 'CA';
$c4->description = 'Independent consultant advising on data architecture. Uses personal email for all correspondence.';
$c4->save();
echo "CONTAM_C1:{$c4->id}:Takeshi Nakamura\n";

// Contamination contact 2: email matches account domain — should NOT be moved
$c5 = BeanFactory::newBean('Contacts');
$c5->first_name  = 'Sarah';
$c5->last_name   = 'Mitchell';
$c5->title       = 'Contracts Manager';
$c5->department  = 'Procurement';
$c5->phone_work  = '(703) 555-0215';
$c5->email1      = 's.mitchell@pinnacledefense.com';
$c5->account_id  = $pinnacle_id;
$c5->primary_address_city  = 'Arlington';
$c5->primary_address_state = 'VA';
$c5->description = 'Primary procurement contact for all defense contracts and vendor agreements.';
$c5->save();
echo "CONTAM_C2:{$c5->id}:Sarah Mitchell\n";

echo "APPLE_ID:{$apple_id}\n";
echo "=== PHP seed complete ===\n";
?>
PHPEOF

docker cp /tmp/cfa_seed.php suitecrm-app:/tmp/cfa_seed.php
PHP_OUT=$(docker exec suitecrm-app php /tmp/cfa_seed.php 2>&1)
echo "$PHP_OUT"

# 4. Save all IDs for verifier
echo "$PHP_OUT" | grep '^USER:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_turner_id.txt
echo "$PHP_OUT" | grep '^ACCT:' > /tmp/cfa_acct_ids.txt

echo "$PHP_OUT" | grep '^REOPEN1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_reopen1_id.txt
echo "$PHP_OUT" | grep '^REOPEN2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_reopen2_id.txt
echo "$PHP_OUT" | grep '^CONTAM_R1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_contam_r1_id.txt

echo "$PHP_OUT" | grep '^INFLATE1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_inflate1_id.txt
echo "$PHP_OUT" | grep '^INFLATE2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_inflate2_id.txt

echo "$PHP_OUT" | grep '^FABRICATED:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_fabricated_id.txt
echo "$PHP_OUT" | grep '^LEGIT_CW1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_legit_cw1_id.txt
echo "$PHP_OUT" | grep '^LEGIT_CW2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_legit_cw2_id.txt

echo "$PHP_OUT" | grep '^LEGIT_ACTIVE1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_legit_active1_id.txt
echo "$PHP_OUT" | grep '^LEGIT_ACTIVE2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_legit_active2_id.txt

echo "$PHP_OUT" | grep '^CONTACT_FIX1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_contact_fix1_id.txt
echo "$PHP_OUT" | grep '^CONTACT_FIX2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_contact_fix2_id.txt
echo "$PHP_OUT" | grep '^CONTACT_FIX3:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_contact_fix3_id.txt
echo "$PHP_OUT" | grep '^CONTAM_C1:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_contam_c1_id.txt
echo "$PHP_OUT" | grep '^CONTAM_C2:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_contam_c2_id.txt

echo "$PHP_OUT" | grep '^APPLE_ID:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_apple_id.txt

# Extract account IDs by name
echo "$PHP_OUT" | grep 'Pinnacle Defense' | grep '^ACCT:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_pinnacle_id.txt
echo "$PHP_OUT" | grep 'Quantum Dynamics' | grep '^ACCT:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_quantum_id.txt
echo "$PHP_OUT" | grep 'Evergreen Health' | grep '^ACCT:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/cfa_evergreen_id.txt

chmod 666 /tmp/cfa_*.txt

# 5. Ensure logged in and navigate to Accounts
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/cfa_initial.png

echo "=== crm_forensic_audit setup complete ==="
echo "User: Alex Turner (aturner)"
echo "Accounts: Pinnacle Defense Systems, Quantum Dynamics Inc, Evergreen Health Partners"
echo "Rule 1: 2 re-opened deals + 1 contamination"
echo "Rule 2: 2 inflated amounts"
echo "Rule 3: 1 fabricated Closed Won + 2 legitimate Closed Won with activities"
echo "Rule 4: 3 misassigned contacts + 2 contamination contacts"
echo "Legitimate active opps: 2"
