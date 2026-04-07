#!/bin/bash
echo "=== Exporting gdpr_user_anonymization_request results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/gdpr_final.png

USER_KWEBER_ID=$(cat /tmp/gdpr_kweber_id.txt 2>/dev/null || echo "0")
USER_SROSSI_ID=$(cat /tmp/gdpr_srossi_id.txt 2>/dev/null || echo "0")
USER_KWAGNER_ID=$(cat /tmp/gdpr_kwagner_id.txt 2>/dev/null || echo "0")
ASSET_ID=$(cat /tmp/gdpr_asset_id.txt 2>/dev/null || echo "0")

# Check Asset state
ASSET_DATA=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE id=$ASSET_ID")
if [ -z "$ASSET_DATA" ] || [ "$ASSET_DATA" = "NULL" ] || [ "$ASSET_DATA" = "0" ]; then
    ASSET_CHECKED_IN="true"
else
    ASSET_CHECKED_IN="false"
fi

# Function to extract user properties safely as JSON
get_user_json() {
    local uid="$1"
    local data=$(snipeit_db_query "SELECT first_name, last_name, username, email, phone, address, city, state, zip, country, employee_num, notes, activated, deleted_at FROM users WHERE id=$uid LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"found\": false}"
        return
    fi
    
    local fname=$(echo "$data" | awk -F'\t' '{print $1}')
    local lname=$(echo "$data" | awk -F'\t' '{print $2}')
    local uname=$(echo "$data" | awk -F'\t' '{print $3}')
    local email=$(echo "$data" | awk -F'\t' '{print $4}')
    local phone=$(echo "$data" | awk -F'\t' '{print $5}')
    local addr=$(echo "$data" | awk -F'\t' '{print $6}')
    local city=$(echo "$data" | awk -F'\t' '{print $7}')
    local state=$(echo "$data" | awk -F'\t' '{print $8}')
    local zip=$(echo "$data" | awk -F'\t' '{print $9}')
    local country=$(echo "$data" | awk -F'\t' '{print $10}')
    local emp_num=$(echo "$data" | awk -F'\t' '{print $11}')
    local notes=$(echo "$data" | awk -F'\t' '{print $12}')
    local activated=$(echo "$data" | awk -F'\t' '{print $13}' | tr -d '[:space:]')
    local deleted=$(echo "$data" | awk -F'\t' '{print $14}')
    
    local is_deleted="false"
    if [ -n "$deleted" ] && [ "$deleted" != "NULL" ]; then
        is_deleted="true"
    fi
    
    echo "{
        \"found\": true,
        \"first_name\": \"$(json_escape "$fname")\",
        \"last_name\": \"$(json_escape "$lname")\",
        \"username\": \"$(json_escape "$uname")\",
        \"email\": \"$(json_escape "$email")\",
        \"phone\": \"$(json_escape "$phone")\",
        \"address\": \"$(json_escape "$addr")\",
        \"city\": \"$(json_escape "$city")\",
        \"state\": \"$(json_escape "$state")\",
        \"zip\": \"$(json_escape "$zip")\",
        \"country\": \"$(json_escape "$country")\",
        \"employee_num\": \"$(json_escape "$emp_num")\",
        \"notes\": \"$(json_escape "$notes")\",
        \"activated\": \"$activated\",
        \"is_deleted\": $is_deleted
    }"
}

KWEBER_JSON=$(get_user_json "$USER_KWEBER_ID")
SROSSI_JSON=$(get_user_json "$USER_SROSSI_ID")
KWAGNER_JSON=$(get_user_json "$USER_KWAGNER_ID")

RESULT_JSON=$(cat << JSONEOF
{
  "asset_checked_in": $ASSET_CHECKED_IN,
  "kweber": $KWEBER_JSON,
  "srossi": $SROSSI_JSON,
  "kwagner": $KWAGNER_JSON
}
JSONEOF
)

safe_write_result "/tmp/gdpr_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/gdpr_result.json"
echo "$RESULT_JSON"
echo "=== gdpr_user_anonymization_request export complete ==="