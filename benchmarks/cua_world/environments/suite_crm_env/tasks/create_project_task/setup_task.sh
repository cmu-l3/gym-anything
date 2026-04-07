#!/bin/bash
echo "=== Setting up create_project_task task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure clean slate for our target names
echo "Cleaning up any existing target records..."
suitecrm_db_query "UPDATE project SET deleted=1 WHERE name='HMC Server Migration Q4'"
suitecrm_db_query "UPDATE project_task SET deleted=1 WHERE name='Pre-migration Site Inspection'"
suitecrm_db_query "UPDATE accounts SET deleted=1 WHERE name='Honduras Medical Center'"

# 2. Seed prerequisites: Account and Project
echo "Seeding prerequisite Account and Project..."
ACC_ID=$(cat /proc/sys/kernel/random/uuid)
PROJ_ID=$(cat /proc/sys/kernel/random/uuid)

suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$ACC_ID', 'Honduras Medical Center', NOW(), NOW(), '1', '1', 0);"
suitecrm_db_query "INSERT INTO project (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$PROJ_ID', 'HMC Server Migration Q4', NOW(), NOW(), '1', '1', 0);"

# Link Account and Project (useful for dashboard visibility)
REL_ID=$(cat /proc/sys/kernel/random/uuid)
suitecrm_db_query "INSERT INTO projects_accounts (id, account_id, project_id, date_modified, deleted) VALUES ('$REL_ID', '$ACC_ID', '$PROJ_ID', NOW(), 0);"

# 3. Record initial project_task count
INITIAL_PT_COUNT=$(suitecrm_count "project_task")
echo "Initial Project Task count: $INITIAL_PT_COUNT"
echo "$INITIAL_PT_COUNT" > /tmp/initial_pt_count.txt
chmod 666 /tmp/initial_pt_count.txt 2>/dev/null || true

# 4. Ensure logged in and navigate to Project Tasks list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=ProjectTask&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_project_task_initial.png

echo "=== create_project_task task setup complete ==="