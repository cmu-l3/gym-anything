#!/bin/bash
set -e
echo "=== Setting up attach_diagnostic_log_to_case task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Create a realistic diagnostic log file
echo "Generating Apache_2k.log data..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/Apache_2k.log << 'EOF'
[Thu Mar 09 08:12:01.345210 2026] [core:error] [pid 12345:tid 140123456789] [client 192.168.1.100:54321] AH00001: Segmentation fault (11), possible memory leak in mod_ssl
[Thu Mar 09 08:14:22.102341 2026] [proxy:error] [pid 12346:tid 140123456790] (111)Connection refused: AH00957: HTTP: attempt to connect to 127.0.0.1:8080 (localhost) failed
[Thu Mar 09 08:15:01.000111 2026] [core:notice] [pid 12345:tid 140123456789] AH00094: Command line: '/usr/sbin/apache2'
[Thu Mar 09 08:18:33.444555 2026] [mpm_event:error] [pid 12345:tid 140123456789] AH00484: server reached MaxRequestWorkers setting, consider raising the MaxRequestWorkers setting
[Thu Mar 09 08:22:11.999888 2026] [core:error] [pid 12345:tid 140123456789] [client 192.168.1.101:54322] AH00001: Segmentation fault (11), possible memory leak in mod_ssl
EOF
chown ga:ga /home/ga/Documents/Apache_2k.log
chmod 644 /home/ga/Documents/Apache_2k.log

# 2. Inject fresh CRM records (Account, Contact, Case) using a PHP script via SuiteCRM Beans
# This ensures correct UUID generation and prevents the agent from reusing old data
echo "Seeding necessary CRM records..."
cat > /tmp/setup_beans.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
require_once('modules/Accounts/Account.php');
require_once('modules/Contacts/Contact.php');
require_once('modules/Cases/aCase.php');

global $current_user;
$current_user = BeanFactory::getBean('Users', '1');

// Delete any existing records with the exact names to ensure clean state
$db = DBManagerFactory::getInstance();
$db->query("UPDATE accounts SET deleted=1 WHERE name='TechCorp Solutions'");
$db->query("UPDATE contacts SET deleted=1 WHERE first_name='Alice' AND last_name='Smith'");
$db->query("UPDATE cases SET deleted=1 WHERE name='Web Server Random Crashes - TechCorp'");

// Create Account
$acc = new Account();
$acc->name = 'TechCorp Solutions';
$acc->save();

// Create Contact
$con = new Contact();
$con->first_name = 'Alice';
$con->last_name = 'Smith';
$con->account_id = $acc->id;
$con->save();
$con->load_relationship('accounts');
$con->accounts->add($acc->id);

// Create Case
$cas = new aCase();
$cas->name = 'Web Server Random Crashes - TechCorp';
$cas->status = 'New';
$cas->priority = 'P2'; // P2 = Medium Priority
$cas->account_id = $acc->id;
$cas->save();
$cas->load_relationship('accounts');
$cas->accounts->add($acc->id);

echo "BEANS_CREATED_SUCCESSFULLY\n";
?>
PHPEOF

docker cp /tmp/setup_beans.php suitecrm-app:/tmp/setup_beans.php
docker exec suitecrm-app php /tmp/setup_beans.php > /dev/null

# 3. Ensure Firefox is open, authenticated, and navigated to the Cases list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Cases&action=index"
sleep 4

# 4. Capture initial state screenshot for trajectory evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="