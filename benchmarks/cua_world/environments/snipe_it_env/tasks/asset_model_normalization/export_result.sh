#!/bin/bash
echo "=== Exporting asset_model_normalization results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot as UI evidence
take_screenshot /tmp/asset_model_normalization_final.png

# Read setup IDs and baselines
CANONICAL_LAPTOP_ID=$(cat /tmp/canonical_laptop_id.txt)
CANONICAL_MONITOR_ID=$(cat /tmp/canonical_monitor_id.txt)
DUP_LAPTOP_IDS=$(cat /tmp/dup_laptop_ids.txt)
DUP_MONITOR_IDS=$(cat /tmp/dup_monitor_ids.txt)
TOTAL_MODELS_BEFORE=$(cat /tmp/total_models_before.txt)
TOTAL_ASSETS_BEFORE=$(cat /tmp/total_assets_before.txt)
TASK_START=$(cat /tmp/task_start_time.txt)

# Gather current state totals
TOTAL_MODELS_AFTER=$(snipeit_db_query "SELECT COUNT(*) FROM models WHERE deleted_at IS NULL" | tr -d '[:space:]')
TOTAL_ASSETS_AFTER=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Helper function to get model info and safely format for JSON
get_model_json() {
    local id="$1"
    local data=$(snipeit_db_query "SELECT id, name, model_number, deleted_at FROM models WHERE id=$id")
    if [ -z "$data" ]; then
        echo "{\"id\": $id, \"found\": false}"
    else
        local name=$(echo "$data" | awk -F'\t' '{print $2}')
        local model_number=$(echo "$data" | awk -F'\t' '{print $3}')
        local deleted_at=$(echo "$data" | awk -F'\t' '{print $4}')
        local is_deleted="false"
        if [ -n "$deleted_at" ] && [ "$deleted_at" != "NULL" ]; then is_deleted="true"; fi
        echo "{\"id\": $id, \"found\": true, \"name\": \"$(json_escape "$name")\", \"model_number\": \"$(json_escape "$model_number")\", \"is_deleted\": $is_deleted}"
    fi
}

# Fetch canonical models
CANON_LAPTOP_JSON=$(get_model_json "$CANONICAL_LAPTOP_ID")
CANON_MONITOR_JSON=$(get_model_json "$CANONICAL_MONITOR_ID")

# Fetch duplicate models
IFS=',' read -ra DL_ARR <<< "$DUP_LAPTOP_IDS"
DUP_L1_JSON=$(get_model_json "${DL_ARR[0]}")
DUP_L2_JSON=$(get_model_json "${DL_ARR[1]}")

IFS=',' read -ra DM_ARR <<< "$DUP_MONITOR_IDS"
DUP_M1_JSON=$(get_model_json "${DM_ARR[0]}")
DUP_M2_JSON=$(get_model_json "${DM_ARR[1]}")

# Fetch reassigned assets
ASSETS_JSON="["
first=true
for i in {1..9}; do
    TAG=$(printf "ASSET-NORM-%02d" $i)
    DATA=$(snipeit_db_query "SELECT model_id FROM assets WHERE asset_tag='$TAG' AND deleted_at IS NULL" | tr -d '[:space:]')
    if [ -z "$DATA" ] || [ "$DATA" = "NULL" ]; then DATA="null"; fi
    if [ "$first" = true ]; then first=false; else ASSETS_JSON+=","; fi
    ASSETS_JSON+="{\"tag\": \"$TAG\", \"model_id\": $DATA}"
done
ASSETS_JSON+="]"

# Generate JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "canonical_laptop_id": $CANONICAL_LAPTOP_ID,
  "canonical_monitor_id": $CANONICAL_MONITOR_ID,
  "models": {
    "canonical_laptop": $CANON_LAPTOP_JSON,
    "canonical_monitor": $CANON_MONITOR_JSON,
    "dup_laptop_1": $DUP_L1_JSON,
    "dup_laptop_2": $DUP_L2_JSON,
    "dup_monitor_1": $DUP_M1_JSON,
    "dup_monitor_2": $DUP_M2_JSON
  },
  "assets": $ASSETS_JSON,
  "baseline_models": $TOTAL_MODELS_BEFORE,
  "baseline_assets": $TOTAL_ASSETS_BEFORE,
  "current_models": $TOTAL_MODELS_AFTER,
  "current_assets": $TOTAL_ASSETS_AFTER
}
JSONEOF
)

safe_write_result "/tmp/asset_model_normalization_result.json" "$RESULT_JSON"
echo "Export complete. Payload written to /tmp/asset_model_normalization_result.json."