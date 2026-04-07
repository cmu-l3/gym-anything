#!/bin/bash
set -e
echo "=== Setting up setup_client_project_portfolio task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrangeHRM is ready
wait_for_http "$ORANGEHRM_URL" 60

# Clean up any previous run data to ensure a fresh start
# 1. Get Customer ID for "Nebula Stream"
CUST_ID=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='Nebula Stream' AND is_deleted=0;" 2>/dev/null | tr -d '[:space:]')

if [ -n "$CUST_ID" ]; then
    log "Cleaning up existing data for customer ID: $CUST_ID"
    
    # Get Project IDs
    PROJ_IDS=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE customer_id=$CUST_ID;" 2>/dev/null)
    
    for PID in $PROJ_IDS; do
        if [ -n "$PID" ]; then
            # Delete activities
            orangehrm_db_query "DELETE FROM ohrm_project_activity WHERE project_id=$PID;"
            # Delete admins
            orangehrm_db_query "DELETE FROM ohrm_project_admin WHERE project_id=$PID;"
            # Delete project
            orangehrm_db_query "DELETE FROM ohrm_project WHERE project_id=$PID;"
        fi
    done
    
    # Delete customer (soft delete is standard in OrangeHRM, but hard delete ensures clean verify)
    orangehrm_db_query "DELETE FROM ohrm_customer WHERE customer_id=$CUST_ID;"
fi

# Record initial counts/max IDs to verify new creation
MAX_CUST_ID=$(orangehrm_db_query "SELECT MAX(customer_id) FROM ohrm_customer;" 2>/dev/null | tr -d '[:space:]')
MAX_PROJ_ID=$(orangehrm_db_query "SELECT MAX(project_id) FROM ohrm_project;" 2>/dev/null | tr -d '[:space:]')

echo "${MAX_CUST_ID:-0}" > /tmp/initial_max_cust_id.txt
echo "${MAX_PROJ_ID:-0}" > /tmp/initial_max_proj_id.txt

log "Initial state recorded. Max Cust ID: ${MAX_CUST_ID:-0}, Max Proj ID: ${MAX_PROJ_ID:-0}"

# Start Firefox and log in
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="