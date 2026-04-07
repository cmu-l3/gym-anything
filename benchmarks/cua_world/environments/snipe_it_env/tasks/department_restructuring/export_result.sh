#!/bin/bash
echo "=== Exporting department_restructuring results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time & screenshot
TASK_END=$(date +%s)
take_screenshot /tmp/task_final.png

# Get company and location IDs for MegaCorp
MEGACORP_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='MegaCorp Industries' LIMIT 1" | tr -d '[:space:]')
HQ_LOC_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%HQ - Main Building%' LIMIT 1" | tr -d '[:space:]')

# Helper function to get department info safely
get_dept_json() {
    local dept_name="$1"
    local data=$(snipeit_db_query "SELECT id, COALESCE(company_id, 0), COALESCE(location_id, 0), COALESCE(manager_id, 0) FROM departments WHERE name='$dept_name' AND deleted_at IS NULL LIMIT 1")
    
    if [ -n "$data" ]; then
        local id=$(echo "$data" | cut -f1)
        local cid=$(echo "$data" | cut -f2)
        local lid=$(echo "$data" | cut -f3)
        local mid=$(echo "$data" | cut -f4)
        echo "{\"found\": true, \"id\": $id, \"company_id\": $cid, \"location_id\": $lid, \"manager_id\": $mid}"
    else
        echo "{\"found\": false}"
    fi
}

# Helper function to get user info safely
get_user_json() {
    local username="$1"
    local data=$(snipeit_db_query "SELECT id, COALESCE(department_id, 0), first_name, last_name, email, jobtitle FROM users WHERE username='$username' AND deleted_at IS NULL LIMIT 1")
    
    if [ -n "$data" ]; then
        local id=$(echo "$data" | cut -f1)
        local did=$(echo "$data" | cut -f2)
        local fname=$(echo "$data" | cut -f3 | tr -d '\n' | tr -d '\r')
        local lname=$(echo "$data" | cut -f4 | tr -d '\n' | tr -d '\r')
        local email=$(echo "$data" | cut -f5 | tr -d '\n' | tr -d '\r')
        local title=$(echo "$data" | cut -f6 | tr -d '\n' | tr -d '\r')
        echo "{\"found\": true, \"id\": $id, \"department_id\": $did, \"first_name\": \"$(json_escape "$fname")\", \"last_name\": \"$(json_escape "$lname")\", \"email\": \"$(json_escape "$email")\", \"jobtitle\": \"$(json_escape "$title")\"}"
    else
        echo "{\"found\": false}"
    fi
}

# Fetch JSON objects
DEVOPS_JSON=$(get_dept_json "DevOps Engineering")
CLOUD_JSON=$(get_dept_json "Cloud Infrastructure")
QA_JSON=$(get_dept_json "Software QA")

DMOORE_JSON=$(get_user_json "dmoore")
ITHOMPSON_JSON=$(get_user_json "ithompson")
RCHEN_JSON=$(get_user_json "rchen")
PPATEL_JSON=$(get_user_json "ppatel")

# Check for collateral damage
snipeit_db_query "SELECT id, department_id FROM users WHERE username NOT IN ('dmoore', 'ithompson', 'rchen', 'ppatel') AND deleted_at IS NULL ORDER BY id" > /tmp/final_user_depts.txt
FINAL_HASH=$(md5sum /tmp/final_user_depts.txt | awk '{print $1}')
INITIAL_HASH=$(cat /tmp/initial_user_depts_hash.txt)

COLLATERAL_DAMAGE="false"
if [ "$FINAL_HASH" != "$INITIAL_HASH" ]; then
    COLLATERAL_DAMAGE="true"
fi

# Build main JSON result
RESULT_JSON=$(cat << EOF
{
  "task_end": $TASK_END,
  "megacorp_id": ${MEGACORP_ID:-0},
  "hq_loc_id": ${HQ_LOC_ID:-0},
  "devops_dept": $DEVOPS_JSON,
  "cloud_dept": $CLOUD_JSON,
  "qa_dept": $QA_JSON,
  "dmoore": $DMOORE_JSON,
  "ithompson": $ITHOMPSON_JSON,
  "rchen": $RCHEN_JSON,
  "ppatel": $PPATEL_JSON,
  "collateral_damage": $COLLATERAL_DAMAGE
}
EOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="