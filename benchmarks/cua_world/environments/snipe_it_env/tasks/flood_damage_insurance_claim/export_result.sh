#!/bin/bash
echo "=== Exporting flood_damage_insurance_claim results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

REPORT_FILE="/home/ga/Desktop/insurance_claim_IC-2025-0342.txt"

FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    RAW_CONTENT=$(cat "$REPORT_FILE" | head -c 5000)
    ESCAPED_CONTENT=$(json_escape "$RAW_CONTENT")
    FILE_CONTENT="\"$ESCAPED_CONTENT\""
    
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    FILE_CONTENT="\"\""
fi

build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.status_id, sl.name, a.notes FROM assets a LEFT JOIN status_labels sl ON a.status_id = sl.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local status_name=$(echo "$data" | awk -F'\t' '{print $2}')
    local notes=$(echo "$data" | awk -F'\t' '{print $3}')
    echo "{\"tag\": \"$tag\", \"found\": true, \"status_name\": \"$(json_escape "$status_name")\", \"notes\": \"$(json_escape "$notes")\"}"
}

FD01=$(build_asset_json "ASSET-FD01")
FD02=$(build_asset_json "ASSET-FD02")
FD03=$(build_asset_json "ASSET-FD03")
FD04=$(build_asset_json "ASSET-FD04")
FD05=$(build_asset_json "ASSET-FD05")
FD06=$(build_asset_json "ASSET-FD06")
FD07=$(build_asset_json "ASSET-FD07")

RESULT_JSON=$(cat << JSONEOF
{
  "assets": {
    "FD01": $FD01,
    "FD02": $FD02,
    "FD03": $FD03,
    "FD04": $FD04,
    "FD05": $FD05,
    "FD06": $FD06,
    "FD07": $FD07
  },
  "report_file": {
    "exists": $FILE_EXISTS,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "content": $FILE_CONTENT
  }
}
JSONEOF
)

safe_write_result "/tmp/flood_damage_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/flood_damage_result.json"
echo "$RESULT_JSON"
echo "=== export complete ==="