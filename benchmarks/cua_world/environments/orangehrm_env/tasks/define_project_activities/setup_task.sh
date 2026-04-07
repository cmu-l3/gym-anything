#!/bin/bash
set -e
echo "=== Setting up define_project_activities task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrangeHRM to be ready
wait_for_http "$ORANGEHRM_URL" 60

# 3. Setup Data: Customer and Project
# We need to ensure 'TechCorp Solutions' and 'Cloud Migration Phase 1' exist, 
# and that the project has NO activities to start with.

echo "Configuring database state..."

# Create Customer if not exists
CUST_CHECK=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='TechCorp Solutions' AND is_deleted=0;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$CUST_CHECK" ]; then
    echo "Creating customer 'TechCorp Solutions'..."
    orangehrm_db_query "INSERT INTO ohrm_customer (name, description, is_deleted) VALUES ('TechCorp Solutions', 'Strategic Enterprise Client', 0);"
fi

# Create Project if not exists
PROJ_CHECK=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE name='Cloud Migration Phase 1' AND is_deleted=0;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$PROJ_CHECK" ]; then
    echo "Creating project 'Cloud Migration Phase 1'..."
    # Get Customer ID
    CUST_ID=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='TechCorp Solutions' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    
    # Insert Project (admin user id 1 is usually the lead)
    orangehrm_db_query "INSERT INTO ohrm_project (customer_id, name, description, is_deleted) VALUES ($CUST_ID, 'Cloud Migration Phase 1', 'Migration of legacy on-prem systems to AWS', 0);"
fi

# CRITICAL: Clean up any existing activities for this project to ensure a clean slate
echo "Cleaning existing activities for project..."
# We need the project ID again
PROJ_ID=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE name='Cloud Migration Phase 1' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

if [ -n "$PROJ_ID" ]; then
    # Hard delete or soft delete existing activities
    orangehrm_db_query "DELETE FROM ohrm_project_activity WHERE project_id=$PROJ_ID;"
    echo "Cleared activities for project ID $PROJ_ID"
else
    echo "ERROR: Could not find project ID after creation attempt."
    exit 1
fi

# 4. Prepare Browser
# Stop any existing Firefox
stop_firefox

# Login and navigate to Project Info > Projects
# The URL for Project List is .../web/index.php/time/viewProjectList (checking OrangeHRM 5 routes)
# Or we can just go to dashboard and let them navigate. 
# Task description says "Navigate to Time > Project Info...", so we should probably start at Dashboard or Time module.
# Let's start at Dashboard to force navigation test.
TARGET_URL="${ORANGEHRM_URL}/web/index.php/dashboard/index"
ensure_orangehrm_logged_in "$TARGET_URL"

# 5. Capture Initial State
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="