#!/bin/bash
echo "=== Setting up configure_company_branding_and_smtp task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record baseline state for anti-gaming checks
INITIAL_ORG_NAME=$(vtiger_db_query "SELECT organizationname FROM vtiger_organizationdetails LIMIT 1" | tr -d '\n\r')
echo "$INITIAL_ORG_NAME" > /tmp/initial_org_name.txt

# Ensure we are logged in and navigate to the CRM Settings homepage
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Vtiger&parent=Settings&view=Index"
sleep 3

# Take initial screenshot showing the Settings dashboard
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Configure Company Details, SMTP, and Configuration Editor"
echo "Agent should navigate through Settings -> Configuration and update the forms."