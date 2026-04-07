#!/bin/bash
echo "=== Setting up create_sales_group_and_reassign_leads task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing group with the target name (Anti-gaming / clean slate)
echo "Cleaning up any pre-existing group..."
vtiger_db_query "
DELETE FROM vtiger_group2role WHERE groupid IN (SELECT groupid FROM vtiger_groups WHERE groupname='Enterprise Sales Team');
DELETE FROM vtiger_group2rs WHERE groupid IN (SELECT groupid FROM vtiger_groups WHERE groupname='Enterprise Sales Team');
DELETE FROM vtiger_group2modules WHERE groupid IN (SELECT groupid FROM vtiger_groups WHERE groupname='Enterprise Sales Team');
DELETE FROM vtiger_users2group WHERE groupid IN (SELECT groupid FROM vtiger_groups WHERE groupname='Enterprise Sales Team');
DELETE FROM vtiger_groups WHERE groupname='Enterprise Sales Team';
"

# 2. Get the Admin user ID
ADMIN_ID=$(vtiger_db_query "SELECT id FROM vtiger_users WHERE user_name='admin' LIMIT 1" | tr -d '[:space:]')
if [ -z "$ADMIN_ID" ]; then
    ADMIN_ID=1
fi

# 3. Setup Leads Data
# Ensure all leads are owned by Admin and none are set to 'Technology' yet to prevent accidental passes
echo "Resetting lead industries and ownership..."
vtiger_db_query "UPDATE vtiger_crmentity SET smownerid=$ADMIN_ID WHERE setype='Leads'"
vtiger_db_query "UPDATE vtiger_leaddetails SET industry='Banking'"

# Find exactly 5 leads and set their industry to 'Technology'
IDS=$(vtiger_db_query "SELECT leadid FROM vtiger_leaddetails LIMIT 5" | tr '\n' ',' | sed 's/,$//')
if [ -n "$IDS" ]; then
    vtiger_db_query "UPDATE vtiger_leaddetails SET industry='Technology' WHERE leadid IN ($IDS)"
    echo "Set 5 leads to 'Technology' industry."
else
    echo "WARNING: Could not find any leads to update."
fi

# 4. Ensure logged in and navigate to Vtiger Home
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

# Verify initial setup logic 
TARGET_LEADS_COUNT=$(vtiger_count "vtiger_leaddetails" "industry='Technology'")
echo "Initial Technology leads count: $TARGET_LEADS_COUNT"
echo "$TARGET_LEADS_COUNT" > /tmp/initial_tech_leads_count.txt

echo "=== Task setup complete ==="