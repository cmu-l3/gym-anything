#!/bin/bash
echo "=== Exporting bulk_csv_asset_import results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/bulk_csv_asset_import_final.png

# Read baseline
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_asset_count)

# Get location ID for "HQ - Floor 2"
LOC_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='HQ - Floor 2' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# Build JSON array of exported assets
ASSETS_JSON="{"
first=true

for i in $(seq -w 1 10); do
    TAG="ENG-LAB-0$(printf "%02d" $i)"
    
    DATA=$(snipeit_db_query "SELECT a.serial, m.name as model_name, a.rtd_location_id, a.purchase_cost, UNIX_TIMESTAMP(a.created_at) FROM assets a LEFT JOIN models m ON a.model_id = m.id WHERE a.asset_tag='${TAG}' AND a.deleted_at IS NULL LIMIT 1")
    
    if [ "$first" = true ]; then first=false; else ASSETS_JSON+=", "; fi
    
    if [ -n "$DATA" ]; then
        SERIAL=$(echo "$DATA" | awk -F'\t' '{print $1}')
        MODEL=$(echo "$DATA" | awk -F'\t' '{print $2}')
        LOC=$(echo "$DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
        COST=$(echo "$DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
        CREATED=$(echo "$DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
        
        LOC_MATCH="false"
        if [ "$LOC" = "$LOC_ID" ] && [ -n "$LOC_ID" ]; then
            LOC_MATCH="true"
        fi
        
        ASSETS_JSON+="\"${TAG}\": {"
        ASSETS_JSON+="\"found\": true, "
        ASSETS_JSON+="\"serial\": \"$(json_escape "$SERIAL")\", "
        ASSETS_JSON+="\"model_name\": \"$(json_escape "$MODEL")\", "
        ASSETS_JSON+="\"loc_match\": ${LOC_MATCH}, "
        ASSETS_JSON+="\"purchase_cost\": \"${COST}\", "
        ASSETS_JSON+="\"created_at\": ${CREATED:-0}"
        ASSETS_JSON+="}"
    else
        ASSETS_JSON+="\"${TAG}\": {\"found\": false}"
    fi
done

ASSETS_JSON+="}"

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": ${TASK_START},
  "initial_count": ${INITIAL_COUNT},
  "current_count": ${CURRENT_COUNT},
  "assets": ${ASSETS_JSON}
}
JSONEOF
)

safe_write_result "/tmp/bulk_csv_asset_import_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/bulk_csv_asset_import_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="