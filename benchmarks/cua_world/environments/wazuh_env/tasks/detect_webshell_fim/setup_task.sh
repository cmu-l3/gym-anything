#!/bin/bash
# pre_task: Setup for detect_webshell_fim task
set -e
echo "=== Setting up detect_webshell_fim task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure target directory exists in container
echo "Ensuring /var/www/html exists in manager container..."
wazuh_exec mkdir -p /var/www/html
wazuh_exec chmod 755 /var/www/html

# 3. Clean state: Remove any existing FIM config for /var/www/html
echo "Cleaning ossec.conf..."
wazuh_exec sed -i '/<directories.*\/var\/www\/html<\/directories>/d' /var/ossec/etc/ossec.conf

# 4. Clean state: Remove custom rule 100050 if exists
echo "Cleaning local_rules.xml..."
wazuh_exec sed -i '/<rule id="100050"/,/<\/rule>/d' /var/ossec/etc/rules/local_rules.xml

# 5. Restart manager to ensure clean baseline
echo "Restarting Wazuh manager..."
restart_wazuh_manager

# 6. Setup Firefox context
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5
# Navigate to configuration editor (Agent 000)
navigate_firefox_to "https://localhost/app/management-configuration#/000"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="