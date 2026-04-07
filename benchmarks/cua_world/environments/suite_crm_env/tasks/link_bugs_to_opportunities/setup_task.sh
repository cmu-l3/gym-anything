#!/bin/bash
echo "=== Setting up link_bugs_to_opportunities task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Record initial relationships state
INITIAL_REL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM relationships WHERE deleted=0")
echo "$INITIAL_REL_COUNT" > /tmp/initial_rel_count.txt

# 3. Create a PHP script to safely seed the specific Opportunity and Bug records via SuiteCRM BeanFactory
cat > /tmp/seed_link_task.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $current_user;
$current_user = BeanFactory::getBean('Users', '1');

// Delete any existing records with these names to ensure a clean state
$db = DBManagerFactory::getInstance();
$db->query("UPDATE opportunities SET deleted=1 WHERE name='GlobalMedia - 1000 Licenses'");
$db->query("UPDATE bugs SET deleted=1 WHERE name='Login page timeout error'");

// Create target Opportunity
$opp = BeanFactory::newBean('Opportunities');
$opp->name = 'GlobalMedia - 1000 Licenses';
$opp->amount = 150000;
$opp->sales_stage = 'Negotiation/Review';
$opp->save();

// Create target Bug
$bug = BeanFactory::newBean('Bugs');
$bug->name = 'Login page timeout error';
$bug->status = 'New';
$bug->priority = 'High';
$bug->type = 'Defect';
$bug->description = 'Users reporting 504 Gateway Timeout intermittently during SSO.';
$bug->save();

echo "Task records seeded.\n";
PHPEOF

# Run the script inside the container
docker cp /tmp/seed_link_task.php suitecrm-app:/var/www/html/seed_link_task.php
docker exec -u www-data suitecrm-app php /var/www/html/seed_link_task.php

# 4. Ensure logged into SuiteCRM and navigate to Home
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="