#!/bin/bash
echo "=== Exporting leased_equipment_return results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# 1. Check Status Label Creation
# ---------------------------------------------------------------
LABEL_DATA=$(snipeit_db_query "SELECT id, type FROM status_labels WHERE name='Returned to Lessor' AND deleted_at IS NULL LIMIT 1")
LABEL_ID=$(echo "$LABEL_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
LABEL_TYPE=$(echo "$LABEL_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

LABEL_FOUND="false"
if [ -n "$LABEL_ID" ]; then
    LABEL_FOUND="true"
fi

# ---------------------------------------------------------------
# 2. Fetch Leased Assets (Apple Financial Services)
# ---------------------------------------------------------------
APPLE_ASSETS_JSON="["
for i in {1..4}; do
    TAG="LEASE-00$i"
    DATA=$(snipeit_db_query "SELECT assigned_to, status_id, notes FROM assets WHERE asset_tag='$TAG' AND deleted_at IS NULL LIMIT 1")
    ASSIGNED=$(echo "$DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    STATUS=$(echo "$DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    NOTES=$(echo "$DATA" | awk -F'\t' '{print $3}')
    
    IS_CHECKED_IN="true"
    if [ -n "$ASSIGNED" ] && [ "$ASSIGNED" != "NULL" ] && [ "$ASSIGNED" != "0" ]; then 
        IS_CHECKED_IN="false"
    fi

    [ $i -gt 1 ] && APPLE_ASSETS_JSON+=","
    APPLE_ASSETS_JSON+="{\"tag\": \"$TAG\", \"is_checked_in\": $IS_CHECKED_IN, \"status_id\": \"$STATUS\", \"notes\": \"$(json_escape "$NOTES")\"}"
done
APPLE_ASSETS_JSON+="]"

# ---------------------------------------------------------------
# 3. Fetch Owned Assets (CDW)
# ---------------------------------------------------------------
CDW_ASSETS_JSON="["
for i in {1..3}; do
    TAG="OWNED-00$i"
    DATA=$(snipeit_db_query "SELECT assigned_to, status_id, notes FROM assets WHERE asset_tag='$TAG' AND deleted_at IS NULL LIMIT 1")
    ASSIGNED=$(echo "$DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    STATUS=$(echo "$DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    NOTES=$(echo "$DATA" | awk -F'\t' '{print $3}')
    
    IS_CHECKED_IN="true"
    if [ -n "$ASSIGNED" ] && [ "$ASSIGNED" != "NULL" ] && [ "$ASSIGNED" != "0" ]; then 
        IS_CHECKED_IN="false"
    fi

    [ $i -gt 1 ] && CDW_ASSETS_JSON+=","
    CDW_ASSETS_JSON+="{\"tag\": \"$TAG\", \"is_checked_in\": $IS_CHECKED_IN, \"status_id\": \"$STATUS\", \"notes\": \"$(json_escape "$NOTES")\"}"
done
CDW_ASSETS_JSON+="]"

# ---------------------------------------------------------------
# 4. Generate JSON Export
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "status_label": {
    "found": $LABEL_FOUND,
    "type": "$(json_escape "$LABEL_TYPE")",
    "id": "${LABEL_ID}"
  },
  "apple_assets": $APPLE_ASSETS_JSON,
  "cdw_assets": $CDW_ASSETS_JSON
}
EOF

# Safely copy to destination
rm -f /tmp/leased_equipment_return_result.json 2>/dev/null || sudo rm -f /tmp/leased_equipment_return_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/leased_equipment_return_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/leased_equipment_return_result.json
chmod 666 /tmp/leased_equipment_return_result.json 2>/dev/null || sudo chmod 666 /tmp/leased_equipment_return_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/leased_equipment_return_result.json"
cat /tmp/leased_equipment_return_result.json
echo "=== Export complete ==="