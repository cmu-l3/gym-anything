#!/bin/bash
echo "=== Exporting link_opps_to_campaign results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Campaign state
# We use UNIX_TIMESTAMP to get an exact comparable timestamp for anti-gaming
CAMP_DATA=$(suitecrm_db_query "SELECT id, IFNULL(actual_cost, 0), UNIX_TIMESTAMP(date_modified) FROM campaigns WHERE name='Spring Tech Conference' AND deleted=0 LIMIT 1")

if [ -n "$CAMP_DATA" ]; then
    CAMP_ID=$(echo "$CAMP_DATA" | awk -F'\t' '{print $1}')
    CAMP_COST=$(echo "$CAMP_DATA" | awk -F'\t' '{print $2}')
    CAMP_MTIME=$(echo "$CAMP_DATA" | awk -F'\t' '{print $3}')
else
    CAMP_ID=""
    CAMP_COST="0"
    CAMP_MTIME="0"
fi

# 2. Query Opportunities state
get_opp_info() {
    local opp_name="$1"
    local data
    data=$(suitecrm_db_query "SELECT IFNULL(campaign_id, ''), UNIX_TIMESTAMP(date_modified) FROM opportunities WHERE name='$opp_name' AND deleted=0 LIMIT 1")
    if [ -n "$data" ]; then
        local c_id=$(echo "$data" | awk -F'\t' '{print $1}')
        local m_time=$(echo "$data" | awk -F'\t' '{print $2}')
        echo "{\"campaign_id\": \"$c_id\", \"mtime\": ${m_time:-0}}"
    else
        echo "{\"campaign_id\": \"\", \"mtime\": 0}"
    fi
}

OPP_ALPHA=$(get_opp_info "Alpha Tech Upgrade")
OPP_BETA=$(get_opp_info "Beta Corp License")
OPP_GAMMA=$(get_opp_info "Gamma LLC Support")

# 3. Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "campaign": {
        "id": "$(json_escape "$CAMP_ID")",
        "actual_cost": $CAMP_COST,
        "mtime": $CAMP_MTIME
    },
    "opportunities": {
        "Alpha Tech Upgrade": $OPP_ALPHA,
        "Beta Corp License": $OPP_BETA,
        "Gamma LLC Support": $OPP_GAMMA
    }
}
EOF

# Safely copy to final location
safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="