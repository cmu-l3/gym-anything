#!/bin/bash
echo "=== Exporting create_account_hierarchy results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/hierarchy_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_account_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_account_count)

# Helper function to get account details as JSON
get_acct_json() {
    local name="$1"
    local data
    # IFNULL is used to prevent empty columns from breaking the tab-delimited parsing
    data=$(suitecrm_db_query "SELECT id, IFNULL(parent_id, ''), IFNULL(industry, ''), IFNULL(billing_address_city, ''), UNIX_TIMESTAMP(date_entered) FROM accounts WHERE name='${name}' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")
    
    if [ -n "$data" ]; then
        local id=$(echo "$data" | awk -F'\t' '{print $1}')
        local pid=$(echo "$data" | awk -F'\t' '{print $2}')
        local ind=$(echo "$data" | awk -F'\t' '{print $3}')
        local city=$(echo "$data" | awk -F'\t' '{print $4}')
        local ts=$(echo "$data" | awk -F'\t' '{print $5}')
        
        echo "{\"found\": true, \"id\": \"$(json_escape "$id")\", \"parent_id\": \"$(json_escape "$pid")\", \"industry\": \"$(json_escape "$ind")\", \"city\": \"$(json_escape "$city")\", \"timestamp\": ${ts:-0}}"
    else
        echo "{\"found\": false}"
    fi
}

echo "Querying database for created accounts..."
PARENT_JSON=$(get_acct_json "Siemens AG")
CHILD1_JSON=$(get_acct_json "Siemens Healthineers")
CHILD2_JSON=$(get_acct_json "Siemens Digital Industries")
CHILD3_JSON=$(get_acct_json "Siemens Mobility")

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": ${TASK_START},
  "initial_count": ${INITIAL_COUNT},
  "current_count": ${CURRENT_COUNT},
  "parent": ${PARENT_JSON},
  "healthineers": ${CHILD1_JSON},
  "digital_industries": ${CHILD2_JSON},
  "mobility": ${CHILD3_JSON}
}
JSONEOF
)

safe_write_result "/tmp/hierarchy_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/hierarchy_result.json"
echo "$RESULT_JSON"
echo "=== create_account_hierarchy export complete ==="