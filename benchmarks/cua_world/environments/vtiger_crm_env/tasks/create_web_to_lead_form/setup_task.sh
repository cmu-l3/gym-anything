#!/bin/bash
echo "=== Setting up create_web_to_lead_form task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Record initial webform count
INITIAL_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_webforms" | tr -d '[:space:]')
echo "Initial webform count: $INITIAL_COUNT"
rm -f /tmp/initial_webform_count.txt 2>/dev/null || true
echo "${INITIAL_COUNT:-0}" > /tmp/initial_webform_count.txt
chmod 666 /tmp/initial_webform_count.txt 2>/dev/null || true

# 3. Verify the target webform does not already exist (clean state)
EXISTING_ID=$(vtiger_db_query "SELECT id FROM vtiger_webforms WHERE name='B2B Landing Page' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ]; then
    echo "WARNING: Target webform already exists, removing for clean state"
    vtiger_db_query "DELETE FROM vtiger_webforms_field WHERE webformid=$EXISTING_ID"
    vtiger_db_query "DELETE FROM vtiger_webforms WHERE id=$EXISTING_ID"
fi

# 4. Ensure logged in and navigate to Webforms list in CRM Settings
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Webforms&parent=Settings&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== create_web_to_lead_form task setup complete ==="
echo "Task: Create 'B2B Landing Page' webform for the Leads module"
echo "Agent should click Add Webform, fill the fields, and set the hidden Lead Source override."