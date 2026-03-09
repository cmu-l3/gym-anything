#!/bin/bash
echo "=== Exporting stolen_device_incident_response results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/incident_final.png

# Read baseline
STOLEN_ASSET_ID=$(cat /tmp/incident_stolen_id.txt 2>/dev/null || echo "0")
STOLEN_ASSET_TAG=$(cat /tmp/incident_stolen_tag.txt 2>/dev/null || echo "ASSET-L007")
DKIM_USER_ID=$(cat /tmp/incident_dkim_id.txt 2>/dev/null || echo "0")
REPLACEMENT_ASSET_ID=$(cat /tmp/incident_replacement_id.txt 2>/dev/null || echo "0")
SL_LOST_ID=$(cat /tmp/incident_lost_status_id.txt 2>/dev/null || echo "0")
INITIAL_TOTAL=$(cat /tmp/incident_total_assets.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# Check stolen laptop state
# ---------------------------------------------------------------
STOLEN_DATA=$(snipeit_db_query "SELECT a.asset_tag, a.status_id, sl.name, a.assigned_to, a.notes FROM assets a JOIN status_labels sl ON a.status_id=sl.id WHERE a.id=$STOLEN_ASSET_ID AND a.deleted_at IS NULL LIMIT 1")
STOLEN_STATUS_NAME=$(echo "$STOLEN_DATA" | awk -F'\t' '{print $3}')
STOLEN_ASSIGNED=$(echo "$STOLEN_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
STOLEN_NOTES=$(echo "$STOLEN_DATA" | awk -F'\t' '{print $5}')

# Is it checked in (assigned_to is null/0)?
STOLEN_CHECKED_IN="false"
if [ -z "$STOLEN_ASSIGNED" ] || [ "$STOLEN_ASSIGNED" = "NULL" ] || [ "$STOLEN_ASSIGNED" = "0" ]; then
    STOLEN_CHECKED_IN="true"
fi

# Is status Lost/Stolen?
STOLEN_IS_LOST="false"
if [ "$STOLEN_STATUS_NAME" = "Lost/Stolen" ]; then
    STOLEN_IS_LOST="true"
fi

# Does note contain incident info?
STOLEN_HAS_INCIDENT_NOTE="false"
if echo "$STOLEN_NOTES" | grep -qi "SI-2025-0042"; then
    STOLEN_HAS_INCIDENT_NOTE="true"
fi

# ---------------------------------------------------------------
# Check replacement asset state
# ---------------------------------------------------------------
REPL_DATA=$(snipeit_db_query "SELECT a.asset_tag, a.assigned_to, a.assigned_type FROM assets a WHERE a.id=$REPLACEMENT_ASSET_ID AND a.deleted_at IS NULL LIMIT 1")
REPL_ASSIGNED=$(echo "$REPL_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

REPL_CHECKED_OUT_TO_DKIM="false"
if [ "$REPL_ASSIGNED" = "$DKIM_USER_ID" ]; then
    REPL_CHECKED_OUT_TO_DKIM="true"
fi

# Check checkout note in action log
REPL_CHECKOUT_NOTE=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$REPLACEMENT_ASSET_ID AND item_type LIKE '%Asset%' AND action_type='checkout' ORDER BY id DESC LIMIT 1" | tr -d '\n')
REPL_NOTE_HAS_INCIDENT="false"
if echo "$REPL_CHECKOUT_NOTE" | grep -qi "SI-2025-0042"; then
    REPL_NOTE_HAS_INCIDENT="true"
fi

# ---------------------------------------------------------------
# Check insurance claim asset
# ---------------------------------------------------------------
INS_DATA=$(snipeit_db_query "SELECT a.asset_tag, a.name, a.serial, sl.name, a.purchase_cost, a.notes, a.warranty_months, a.purchase_date FROM assets a JOIN status_labels sl ON a.status_id=sl.id WHERE a.asset_tag='ASSET-L012' AND a.deleted_at IS NULL LIMIT 1")
INS_FOUND="false"
INS_NAME=""
INS_SERIAL=""
INS_STATUS=""
INS_COST=""
INS_NOTES=""
INS_WARRANTY=""
if [ -n "$INS_DATA" ]; then
    INS_FOUND="true"
    INS_NAME=$(echo "$INS_DATA" | awk -F'\t' '{print $2}')
    INS_SERIAL=$(echo "$INS_DATA" | awk -F'\t' '{print $3}')
    INS_STATUS=$(echo "$INS_DATA" | awk -F'\t' '{print $4}')
    INS_COST=$(echo "$INS_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    INS_NOTES=$(echo "$INS_DATA" | awk -F'\t' '{print $6}')
    INS_WARRANTY=$(echo "$INS_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
fi

# Control asset check (ASSET-L001 should be unchanged)
CONTROL_CURRENT=$(snipeit_db_query "SELECT status_id, assigned_to FROM assets WHERE asset_tag='ASSET-L001' AND deleted_at IS NULL")
CONTROL_BASELINE=$(cat /tmp/incident_control_baseline.txt 2>/dev/null || echo "")
CONTROL_STATUS_CURR=$(echo "$CONTROL_CURRENT" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CONTROL_ASSIGNED_CURR=$(echo "$CONTROL_CURRENT" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
CONTROL_STATUS_BASE=$(echo "$CONTROL_BASELINE" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CONTROL_ASSIGNED_BASE=$(echo "$CONTROL_BASELINE" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
CONTROL_UNCHANGED="false"
if [ "$CONTROL_STATUS_CURR" = "$CONTROL_STATUS_BASE" ] && [ "$CONTROL_ASSIGNED_CURR" = "$CONTROL_ASSIGNED_BASE" ]; then
    CONTROL_UNCHANGED="true"
fi

CURRENT_TOTAL=$(get_asset_count)

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "stolen_asset": {
    "tag": "$(json_escape "$STOLEN_ASSET_TAG")",
    "checked_in": $STOLEN_CHECKED_IN,
    "is_lost_stolen": $STOLEN_IS_LOST,
    "status_name": "$(json_escape "$STOLEN_STATUS_NAME")",
    "has_incident_note": $STOLEN_HAS_INCIDENT_NOTE,
    "notes": "$(json_escape "$STOLEN_NOTES")"
  },
  "replacement_asset": {
    "tag": "ASSET-L009",
    "checked_out_to_dkim": $REPL_CHECKED_OUT_TO_DKIM,
    "checkout_note": "$(json_escape "$REPL_CHECKOUT_NOTE")",
    "note_has_incident": $REPL_NOTE_HAS_INCIDENT
  },
  "insurance_asset": {
    "found": $INS_FOUND,
    "name": "$(json_escape "$INS_NAME")",
    "serial": "$(json_escape "$INS_SERIAL")",
    "status": "$(json_escape "$INS_STATUS")",
    "cost": "$INS_COST",
    "notes": "$(json_escape "$INS_NOTES")",
    "warranty_months": "$INS_WARRANTY"
  },
  "control_asset_unchanged": $CONTROL_UNCHANGED,
  "initial_total_assets": $INITIAL_TOTAL,
  "current_total_assets": $CURRENT_TOTAL,
  "dkim_user_id": $DKIM_USER_ID
}
JSONEOF
)

safe_write_result "/tmp/stolen_device_incident_response_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/stolen_device_incident_response_result.json"
echo "$RESULT_JSON"
echo "=== stolen_device_incident_response export complete ==="
