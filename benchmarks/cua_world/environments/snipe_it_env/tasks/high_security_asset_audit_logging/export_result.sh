#!/bin/bash
echo "=== Exporting high_security_asset_audit_logging results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/audit_task_final.png

START_TIME_SQL=$(cat /tmp/audit_task_start_sql.txt 2>/dev/null)

# Helper function to get asset status and format it into JSON
build_asset_json() {
    local tag="$1"
    
    # Get basic asset properties
    local asset_data=$(snipeit_db_query "SELECT a.id, a.next_audit_date, l.name, sl.name FROM assets a LEFT JOIN locations l ON a.location_id=l.id LEFT JOIN status_labels sl ON a.status_id=sl.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    
    if [ -z "$asset_data" ]; then
        echo "\"$tag\": {\"found\": false}"
        return
    fi
    
    local a_id=$(echo "$asset_data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local a_next=$(echo "$asset_data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local a_loc=$(echo "$asset_data" | awk -F'\t' '{print $3}')
    local a_stat=$(echo "$asset_data" | awk -F'\t' '{print $4}')
    
    # Check if a physical audit was logged for this asset since the task started
    local audit_count=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_id=$a_id AND item_type='App\\\\Models\\\\Asset' AND action_type='audit' AND created_at >= '$START_TIME_SQL'" | tr -d '[:space:]')
    
    local is_audited="false"
    if [ -n "$audit_count" ] && [ "$audit_count" -gt 0 ]; then
        is_audited="true"
    fi
    
    echo "\"$tag\": {\"found\": true, \"next_audit_date\": \"$a_next\", \"location\": \"$(json_escape "$a_loc")\", \"status\": \"$(json_escape "$a_stat")\", \"audited\": $is_audited}"
}

# Collect details for all 5 target assets
JSON_ASSETS="{"
JSON_ASSETS+="$(build_asset_json "SEC-LPT-01"),"
JSON_ASSETS+="$(build_asset_json "SEC-LPT-02"),"
JSON_ASSETS+="$(build_asset_json "SEC-LPT-03"),"
JSON_ASSETS+="$(build_asset_json "SEC-LPT-04"),"
JSON_ASSETS+="$(build_asset_json "SEC-LPT-05")"
JSON_ASSETS+="}"

# Check for collateral damage: Did they audit any assets OTHER than SEC-LPT-* ?
COLLATERAL_AUDITS=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs al JOIN assets a ON al.item_id=a.id WHERE al.item_type='App\\\\Models\\\\Asset' AND al.action_type='audit' AND al.created_at >= '$START_TIME_SQL' AND a.asset_tag NOT LIKE 'SEC-LPT-%'" | tr -d '[:space:]')
if [ -z "$COLLATERAL_AUDITS" ]; then
    COLLATERAL_AUDITS=0
fi

# Build complete result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "assets": $JSON_ASSETS,
  "collateral_audits": $COLLATERAL_AUDITS,
  "start_time_sql": "$START_TIME_SQL"
}
JSONEOF
)

safe_write_result "/tmp/high_security_asset_audit_logging_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/high_security_asset_audit_logging_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="