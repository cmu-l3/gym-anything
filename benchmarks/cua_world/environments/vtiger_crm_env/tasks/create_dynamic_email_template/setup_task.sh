#!/bin/bash
echo "=== Setting up create_dynamic_email_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Verify the target template does not already exist (clean state)
echo "Cleaning up any existing templates with the target name..."
EXISTING_ID=$(vtiger_db_query "SELECT templateid FROM vtiger_emailtemplates WHERE templatename='Standard Post-Demo Follow-up' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ]; then
    echo "WARNING: Template already exists, removing it to ensure clean state."
    vtiger_db_query "DELETE FROM vtiger_emailtemplates WHERE templateid=$EXISTING_ID"
fi

# 2. Ensure logged in and navigate to Email Templates list view
# Email Templates are typically at index.php?module=EmailTemplates&parent=Settings&view=List
echo "Logging in and navigating to Email Templates..."
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=EmailTemplates&parent=Settings&view=List"
sleep 4

# 3. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== create_dynamic_email_template task setup complete ==="
echo "Task: Create 'Standard Post-Demo Follow-up' email template with dynamic merge tags."