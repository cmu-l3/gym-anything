#!/bin/bash
echo "=== Exporting hostname_standardization_remediation results ==="

source /workspace/scripts/task_utils.sh

# Take final snapshot of application
take_screenshot /tmp/hostname_standardization_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ASSETS_JSON="{"
first=true

# Pull the current data for all 7 injected assets
for i in {1..7}; do
    tag="ASSET-800$i"
    data=$(snipeit_db_query "SELECT name, UNIX_TIMESTAMP(updated_at) FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    
    if [ "$first" = true ]; then first=false; else ASSETS_JSON+=","; fi
    
    if [ -z "$data" ]; then
        ASSETS_JSON+="\"$tag\": {\"found\": false}"
    else
        name=$(echo "$data" | awk -F'\t' '{print $1}')
        updated=$(echo "$data" | awk -F'\t' '{print $2}')
        ASSETS_JSON+="\"$tag\": {\"found\": true, \"name\": \"$(json_escape "$name")\", \"updated_at\": $updated}"
    fi
done
ASSETS_JSON+="}"

# Structure JSON safely
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $TASK_START,
  "assets": $ASSETS_JSON
}
JSONEOF
)

safe_write_result "/tmp/hostname_standardization_result.json" "$RESULT_JSON"

echo "Results successfully extracted to /tmp/hostname_standardization_result.json"
echo "=== export complete ==="