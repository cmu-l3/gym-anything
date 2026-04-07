#!/bin/bash
echo "=== Exporting cybersecurity_incident_quarantine results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Verify Status Label Existence
LABEL_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Quarantined - Forensic Hold' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
LABEL_UNDEPLOYABLE="0"
if [ -n "$LABEL_ID" ]; then
    # In Snipe-IT, Undeployable is denoted by deployable=0, pending=0, archived=0
    LABEL_UNDEPLOYABLE=$(snipeit_db_query "SELECT CASE WHEN deployable=0 AND pending=0 AND archived=0 THEN 1 ELSE 0 END FROM status_labels WHERE id=$LABEL_ID" | tr -d '[:space:]')
fi

# 2. Extract Asset Details
get_asset_details() {
    local name="$1"
    local data=$(snipeit_db_query "SELECT id, assigned_to, status_id, notes FROM assets WHERE name='$name' AND deleted_at IS NULL LIMIT 1")
    
    if [ -z "$data" ]; then
        echo "{\"found\": false}"
        return
    fi
    
    local id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local assigned=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local status=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    local notes=$(echo "$data" | awk -F'\t' '{print $4}')
    
    # Check action logs for checkins during the task
    local checkins=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_type='App\\\\Models\\\\Asset' AND action_type='checkin' AND item_id=$id AND created_at >= FROM_UNIXTIME($START_TIME)" | tr -d '[:space:]')
    
    echo "{\"found\": true, \"id\": \"$id\", \"assigned_to\": \"$assigned\", \"status_id\": \"$status\", \"notes\": \"$(json_escape "$notes")\", \"checkins\": $checkins}"
}

T1_JSON=$(get_asset_details "LPT-MKT-04")
T2_JSON=$(get_asset_details "LPT-SALES-11")
T3_JSON=$(get_asset_details "LPT-HR-02")
C1_JSON=$(get_asset_details "LPT-EXEC-01")
C2_JSON=$(get_asset_details "LPT-DEV-09")

# 3. Build Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $START_TIME,
  "label_id": "${LABEL_ID:-}",
  "label_undeployable": "${LABEL_UNDEPLOYABLE:-0}",
  "LPT-MKT-04": $T1_JSON,
  "LPT-SALES-11": $T2_JSON,
  "LPT-HR-02": $T3_JSON,
  "LPT-EXEC-01": $C1_JSON,
  "LPT-DEV-09": $C2_JSON
}
JSONEOF
)

safe_write_result "/tmp/quarantine_result.json" "$RESULT_JSON"

echo "Result JSON written to /tmp/quarantine_result.json"
cat /tmp/quarantine_result.json
echo "=== Export complete ==="