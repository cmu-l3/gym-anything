#!/bin/bash
echo "=== Exporting fleet_telematics_installation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM evidence if needed
take_screenshot /tmp/telematics_final.png

# Helper: Build vehicles JSON
build_veh_json() {
  local tag="$1"
  local data=$(snipeit_db_query "SELECT a.id, sl.name, a.notes FROM assets a LEFT JOIN status_labels sl ON a.status_id=sl.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
  if [ -z "$data" ]; then
      echo "\"$tag\": {\"found\":false}"
      return
  fi
  local v_id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
  local v_status=$(echo "$data" | awk -F'\t' '{print $2}')
  local v_notes=$(echo "$data" | awk -F'\t' '{print $3}')
  if [ -z "$v_id" ]; then v_id="null"; fi
  echo "\"$tag\": {\"found\":true, \"id\":$v_id, \"status_name\":\"$(json_escape "$v_status")\", \"notes\":\"$(json_escape "$v_notes")\"}"
}

# 1. Fetch parent vehicles state
VEH_JSON="{"
VEH_JSON+=$(build_veh_json "VEH-101")
VEH_JSON+=","
VEH_JSON+=$(build_veh_json "VEH-102")
VEH_JSON+=","
VEH_JSON+=$(build_veh_json "VEH-103")
VEH_JSON+="}"

# 2. Fetch telematics assets state
TELEM_JSON="["
first=true
for tag in DASH-01 DASH-02 DASH-03 ELD-01 ELD-02 ELD-03; do
  if [ "$first" = true ]; then first=false; else TELEM_JSON+=","; fi
  
  DATA=$(snipeit_db_query "SELECT a.id, a.purchase_cost, a.order_number, a.assigned_type, a.assigned_to, m.name, c.name, man.name FROM assets a LEFT JOIN models m ON a.model_id=m.id LEFT JOIN categories c ON m.category_id=c.id LEFT JOIN manufacturers man ON m.manufacturer_id=man.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
  
  if [ -z "$DATA" ]; then
     TELEM_JSON+="{\"tag\":\"$tag\", \"found\":false}"
     continue
  fi
  
  A_ID=$(echo "$DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
  A_COST=$(echo "$DATA" | awk -F'\t' '{print $2}')
  A_ORDER=$(echo "$DATA" | awk -F'\t' '{print $3}')
  A_ATYPE=$(echo "$DATA" | awk -F'\t' '{print $4}')
  A_ATO=$(echo "$DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
  A_MOD=$(echo "$DATA" | awk -F'\t' '{print $6}')
  A_CAT=$(echo "$DATA" | awk -F'\t' '{print $7}')
  A_MAN=$(echo "$DATA" | awk -F'\t' '{print $8}')
  
  if [ -z "$A_ID" ]; then A_ID="null"; fi
  if [ -z "$A_ATO" ] || [ "$A_ATO" == "NULL" ]; then A_ATO="null"; fi
  
  # Check for checkout notes in action logs
  NOTE_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_id=$A_ID AND action_type='checkout' AND note LIKE '%Q3 Telematics Install%'" | tr -d '[:space:]')
  CHECKOUT_NOTE_FOUND="false"
  if [ "$NOTE_COUNT" -gt 0 ]; then CHECKOUT_NOTE_FOUND="true"; fi
  
  TELEM_JSON+="{\"tag\":\"$tag\", \"found\":true, \"id\":$A_ID, \"cost\":\"$A_COST\", \"order\":\"$(json_escape "$A_ORDER")\", \"assigned_type\":\"$(json_escape "$A_ATYPE")\", \"assigned_to\":$A_ATO, \"model\":\"$(json_escape "$A_MOD")\", \"category\":\"$(json_escape "$A_CAT")\", \"manufacturer\":\"$(json_escape "$A_MAN")\", \"checkout_note_found\":$CHECKOUT_NOTE_FOUND}"
done
TELEM_JSON+="]"

# Build final structure
RESULT_JSON=$(cat << JSONEOF
{
  "vehicles": $VEH_JSON,
  "telematics": $TELEM_JSON
}
JSONEOF
)

# Use safe write
safe_write_result "/tmp/fleet_telematics_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/fleet_telematics_result.json"
echo "=== fleet_telematics_installation export complete ==="