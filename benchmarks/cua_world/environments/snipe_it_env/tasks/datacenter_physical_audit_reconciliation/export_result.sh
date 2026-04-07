#!/bin/bash
echo "=== Exporting datacenter_physical_audit_reconciliation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/datacenter_audit_final.png

LOC_A_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Datacenter - Rack A' LIMIT 1" | tr -d '[:space:]')
SL_LOST_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Lost/Stolen' LIMIT 1" | tr -d '[:space:]')
if [ -z "$SL_LOST_ID" ]; then
    SL_LOST_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE type='archived' LIMIT 1" | tr -d '[:space:]')
fi

INITIAL_AUDITS=$(cat /tmp/initial_audit_count.txt 2>/dev/null || echo "0")
CURRENT_AUDITS=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='audit'" | tr -d '[:space:]')

build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, location_id, rtd_location_id, status_id, next_audit_date, notes FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local loc_id=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local rtd_loc_id=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    local status_id=$(echo "$data" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    local next_audit_date=$(echo "$data" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    local notes=$(echo "$data" | awk -F'\t' '{print $6}')

    local audit_log=$(snipeit_db_query "SELECT note, created_at FROM action_logs WHERE item_id='$id' AND item_type='App\\\\Models\\\\Asset' AND action_type='audit' ORDER BY id DESC LIMIT 1")
    local audit_logged="false"
    local audit_note=""
    if [ -n "$audit_log" ]; then
        audit_logged="true"
        audit_note=$(echo "$audit_log" | awk -F'\t' '{print $1}')
    fi

    echo "{\"tag\": \"$tag\", \"found\": true, \"id\": \"$id\", \"location_id\": \"$loc_id\", \"rtd_location_id\": \"$rtd_loc_id\", \"status_id\": \"$status_id\", \"next_audit_date\": \"$next_audit_date\", \"notes\": \"$(json_escape "$notes")\", \"audit_logged\": $audit_logged, \"audit_note\": \"$(json_escape "$audit_note")\"}"
}

A01=$(build_asset_json "SRV-RACKA-01")
A02=$(build_asset_json "SRV-RACKA-02")
A03=$(build_asset_json "SRV-RACKA-03")
A04=$(build_asset_json "SRV-RACKA-04")
B99=$(build_asset_json "SRV-RACKB-99")

RESULT_JSON=$(cat << JSONEOF
{
  "loc_a_id": "$LOC_A_ID",
  "sl_lost_id": "$SL_LOST_ID",
  "initial_audits": $INITIAL_AUDITS,
  "current_audits": $CURRENT_AUDITS,
  "assets": {
    "SRV-RACKA-01": $A01,
    "SRV-RACKA-02": $A02,
    "SRV-RACKA-03": $A03,
    "SRV-RACKA-04": $A04,
    "SRV-RACKB-99": $B99
  }
}
JSONEOF
)

safe_write_result "/tmp/datacenter_audit_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/datacenter_audit_result.json"
echo "$RESULT_JSON"
echo "=== export complete ==="