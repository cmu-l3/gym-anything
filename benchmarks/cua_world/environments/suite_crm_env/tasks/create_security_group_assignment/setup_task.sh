#!/bin/bash
echo "=== Setting up create_security_group_assignment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Create PHP script to seed realistic base records (User & Accounts)
cat > /tmp/setup_records.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

// Run as admin
global $current_user;
$current_user = BeanFactory::getBean('Users', '1');

$db = DBManagerFactory::getInstance();

// Clean up any existing records matching our test data
$db->query("UPDATE securitygroups SET deleted=1 WHERE name='APAC Sales Region'");
$db->query("UPDATE users SET deleted=1 WHERE last_name='Lin'");
$db->query("UPDATE accounts SET deleted=1 WHERE name='Tokyo Electronics KK' OR name='Tokyo Distribution Partners'");

// 1. Create User
$user = BeanFactory::newBean('Users');
$user->user_name = 'alin';
$user->first_name = 'Akiko';
$user->last_name = 'Lin';
$user->status = 'Active';
$user->save();

// 2. Create Target Account
$acc1 = BeanFactory::newBean('Accounts');
$acc1->name = 'Tokyo Electronics KK';
$acc1->billing_address_city = 'Tokyo';
$acc1->billing_address_country = 'Japan';
$acc1->save();

// 3. Create Distractor Account
$acc2 = BeanFactory::newBean('Accounts');
$acc2->name = 'Tokyo Distribution Partners';
$acc2->billing_address_city = 'Tokyo';
$acc2->billing_address_country = 'Japan';
$acc2->save();

echo "Base records successfully seeded.\n";
PHPEOF

# Execute PHP script inside the SuiteCRM application container
echo "Seeding base records in SuiteCRM..."
docker cp /tmp/setup_records.php suitecrm-app:/tmp/setup_records.php
docker exec suitecrm-app php /tmp/setup_records.php

# Ensure user is logged in and sitting on the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== create_security_group_assignment task setup complete ==="