#!/bin/bash
echo "=== Setting up customize_contact_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Get the Tab ID for the Contacts module
TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Contacts' LIMIT 1" | tr -d '[:space:]')
TABID=${TABID:-4} # Fallback to 4 which is the default for Contacts
echo "Contacts Tab ID: $TABID"

# 2. Reset the layout to a clean default state to prevent false positives/gaming
echo "Resetting field configurations to default..."
# Turn off summary view for target fields
vtiger_db_query "UPDATE vtiger_field SET summaryfield=0 WHERE fieldname IN ('title', 'mobile', 'department') AND tabid=$TABID"
# Make email optional (E~O = Email~Optional)
vtiger_db_query "UPDATE vtiger_field SET typeofdata='E~O' WHERE fieldname='email' AND tabid=$TABID"

# 3. Ensure logged in and navigate to Vtiger CRM dashboard
# Agent will need to figure out how to navigate to the settings gear icon
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/customize_contact_layout_initial.png

echo "=== customize_contact_layout task setup complete ==="
echo "Task: Customize Contacts module layout"
echo "Agent should navigate to Settings > Module Layouts & Fields, modify Title, Mobile, Department, and Email."