#!/bin/bash
echo "=== Exporting ip_camera_network_provisioning results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

echo "{" > /tmp/cameras.json
first=true
for i in {1..6}; do
    TAG="CAM-010$i"
    
    # Extract API data
    API_OUT=$(snipeit_api GET "hardware/bytag/$TAG" "" 2>/dev/null || echo "{}")
    if [ -z "$API_OUT" ]; then API_OUT="{}"; fi
    
    # Extract DB data raw
    DB_OUT=$(docker exec snipeit-db mysql -u snipeit -psnipeit_pass snipeit -e "SELECT * FROM assets WHERE asset_tag='$TAG' AND deleted_at IS NULL\G" 2>/dev/null || echo "")
    
    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> /tmp/cameras.json
    fi
    
    echo "\"$TAG\": {" >> /tmp/cameras.json
    echo "\"api\": $API_OUT," >> /tmp/cameras.json
    echo "\"db\": \"$(json_escape "$DB_OUT")\"" >> /tmp/cameras.json
    echo "}" >> /tmp/cameras.json
done
echo "}" >> /tmp/cameras.json

CURRENT_ASSET_COUNT=$(get_asset_count)
INITIAL_ASSET_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")
LOC_CHICAGO=$(cat /tmp/loc_chicago_id.txt 2>/dev/null || echo "0")
STATUS_DEFECTIVE=$(cat /tmp/status_defective_id.txt 2>/dev/null || echo "0")

RESULT_JSON=$(cat <<EOF
{
  "cameras": $(cat /tmp/cameras.json),
  "current_asset_count": $CURRENT_ASSET_COUNT,
  "initial_asset_count": $INITIAL_ASSET_COUNT,
  "loc_chicago_id": "$LOC_CHICAGO",
  "status_defective_id": "$STATUS_DEFECTIVE"
}
EOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="