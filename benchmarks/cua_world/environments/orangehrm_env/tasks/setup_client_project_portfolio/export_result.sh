#!/bin/bash
set -e
echo "=== Exporting setup_client_project_portfolio results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_CUST_ID=$(cat /tmp/initial_max_cust_id.txt 2>/dev/null || echo "0")
INITIAL_MAX_PROJ_ID=$(cat /tmp/initial_max_proj_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
CUSTOMER_FOUND="false"
CUSTOMER_NAME=""
CUSTOMER_DESC=""
CUSTOMER_ID=""
NEW_CUSTOMER_CREATED="false"

PROJECT_FOUND="false"
PROJECT_NAME=""
PROJECT_DESC=""
PROJECT_ID=""
NEW_PROJECT_CREATED="false"

ADMIN_ASSIGNED="false"
ADMIN_EMP_NUMBER=""

ACTIVITY_1_FOUND="false"
ACTIVITY_2_FOUND="false"

# 1. Verify Customer
CUST_ROW=$(orangehrm_db_query "SELECT customer_id, name, description FROM ohrm_customer WHERE name='Nebula Stream' AND is_deleted=0 LIMIT 1;" 2>/dev/null)
if [ -n "$CUST_ROW" ]; then
    CUSTOMER_FOUND="true"
    CUSTOMER_ID=$(echo "$CUST_ROW" | awk '{print $1}')
    CUSTOMER_NAME=$(echo "$CUST_ROW" | awk '{print $2}') # Simple awk might fail on spaces, using query for specifics below is safer, but this is a flag check
    
    # Verify exact description handling spaces
    CUSTOMER_DESC=$(orangehrm_db_query "SELECT description FROM ohrm_customer WHERE customer_id=$CUSTOMER_ID;" 2>/dev/null)
    
    if [ "$CUSTOMER_ID" -gt "$INITIAL_MAX_CUST_ID" ]; then
        NEW_CUSTOMER_CREATED="true"
    fi
fi

# 2. Verify Project (if customer exists)
if [ "$CUSTOMER_FOUND" = "true" ]; then
    PROJ_ROW=$(orangehrm_db_query "SELECT project_id, description FROM ohrm_project WHERE customer_id=$CUSTOMER_ID AND name='Legacy System Migration' AND is_deleted=0 LIMIT 1;" 2>/dev/null)
    if [ -n "$PROJ_ROW" ]; then
        PROJECT_FOUND="true"
        PROJECT_ID=$(echo "$PROJ_ROW" | awk '{print $1}')
        PROJECT_DESC=$(orangehrm_db_query "SELECT description FROM ohrm_project WHERE project_id=$PROJECT_ID;" 2>/dev/null)
        
        if [ "$PROJECT_ID" -gt "$INITIAL_MAX_PROJ_ID" ]; then
            NEW_PROJECT_CREATED="true"
        fi
        
        # 3. Verify Project Admin
        # We need the admin's emp_number. Usually Admin is 1, but we check linkages.
        ADMIN_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_admin WHERE project_id=$PROJECT_ID;" 2>/dev/null | tr -d '[:space:]')
        if [ "${ADMIN_COUNT:-0}" -gt 0 ]; then
            ADMIN_ASSIGNED="true"
        fi
        
        # 4. Verify Activities
        ACT1_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_activity WHERE project_id=$PROJECT_ID AND name='Code Analysis' AND is_deleted=0;" 2>/dev/null | tr -d '[:space:]')
        if [ "${ACT1_COUNT:-0}" -gt 0 ]; then
            ACTIVITY_1_FOUND="true"
        fi
        
        ACT2_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_project_activity WHERE project_id=$PROJECT_ID AND name='Data Transfer' AND is_deleted=0;" 2>/dev/null | tr -d '[:space:]')
        if [ "${ACT2_COUNT:-0}" -gt 0 ]; then
            ACTIVITY_2_FOUND="true"
        fi
    fi
fi

# JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "customer_found": $CUSTOMER_FOUND,
    "customer_desc": "$CUSTOMER_DESC",
    "new_customer_created": $NEW_CUSTOMER_CREATED,
    "project_found": $PROJECT_FOUND,
    "project_desc": "$PROJECT_DESC",
    "new_project_created": $NEW_PROJECT_CREATED,
    "admin_assigned": $ADMIN_ASSIGNED,
    "activity_1_found": $ACTIVITY_1_FOUND,
    "activity_2_found": $ACTIVITY_2_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="