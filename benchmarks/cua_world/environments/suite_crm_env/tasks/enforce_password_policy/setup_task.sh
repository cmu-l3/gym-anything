#!/bin/bash
echo "=== Setting up enforce_password_policy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Reset password settings to ensure a clean starting state (Anti-gaming)
echo "Resetting SuiteCRM password settings to default..."
cat > /tmp/reset_pwd.php << 'EOF'
<?php
error_reporting(0);
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
require_once('modules/Configurator/Configurator.php');

$cfg = new Configurator();
// Clear existing password settings
$cfg->config['passwordsetting']['minpwdlength'] = '';
$cfg->config['passwordsetting']['maxpwdlength'] = '';
$cfg->config['passwordsetting']['oneupper'] = '';
$cfg->config['passwordsetting']['onelower'] = '';
$cfg->config['passwordsetting']['onenumber'] = '';
$cfg->config['passwordsetting']['onespecial'] = '';

$cfg->handleOverride();
echo "Password settings cleared.\n";
EOF

docker cp /tmp/reset_pwd.php suitecrm-app:/tmp/reset_pwd.php
docker exec suitecrm-app php /tmp/reset_pwd.php 2>/dev/null || true

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure logged in and navigate to Admin panel directly to save agent time 
#    and focus on the specific settings form
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Administration&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== enforce_password_policy task setup complete ==="
echo "Task: Enforce Corporate Password Security Policy"
echo "Agent should click Password Management and configure the complexity rules."