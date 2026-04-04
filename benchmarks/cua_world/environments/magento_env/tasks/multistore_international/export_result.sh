#!/bin/bash
# Export script for Multi-Store International task

echo "=== Exporting Multi-Store Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_GROUP_COUNT=$(cat /tmp/initial_group_count 2>/dev/null || echo "0")
INITIAL_STORE_COUNT=$(cat /tmp/initial_store_count 2>/dev/null || echo "0")

CURRENT_GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM store_group" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
CURRENT_STORE_COUNT=$(magento_query "SELECT COUNT(*) FROM store" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# 1. Check for Store Group "NestWell Europe"
GROUP_DATA=$(magento_query "SELECT group_id, name, root_category_id FROM store_group WHERE LOWER(TRIM(name)) LIKE '%nestwell%europe%' LIMIT 1" 2>/dev/null | tail -1)
GROUP_ID=$(echo "$GROUP_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
GROUP_NAME=$(echo "$GROUP_DATA" | awk -F'\t' '{print $2}')
GROUP_ROOT_CAT=$(echo "$GROUP_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

GROUP_FOUND="false"
[ -n "$GROUP_ID" ] && GROUP_FOUND="true"

# 2. Check for Store Views
# French View
FR_VIEW_DATA=$(magento_query "SELECT store_id, code, group_id, is_active FROM store WHERE code='nestwell_fr' LIMIT 1" 2>/dev/null | tail -1)
FR_STORE_ID=$(echo "$FR_VIEW_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
FR_CODE=$(echo "$FR_VIEW_DATA" | awk -F'\t' '{print $2}')
FR_GROUP_ID=$(echo "$FR_VIEW_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
FR_ACTIVE=$(echo "$FR_VIEW_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')

FR_FOUND="false"
[ -n "$FR_STORE_ID" ] && FR_FOUND="true"

# German View
DE_VIEW_DATA=$(magento_query "SELECT store_id, code, group_id, is_active FROM store WHERE code='nestwell_de' LIMIT 1" 2>/dev/null | tail -1)
DE_STORE_ID=$(echo "$DE_VIEW_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
DE_CODE=$(echo "$DE_VIEW_DATA" | awk -F'\t' '{print $2}')
DE_GROUP_ID=$(echo "$DE_VIEW_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
DE_ACTIVE=$(echo "$DE_VIEW_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')

DE_FOUND="false"
[ -n "$DE_STORE_ID" ] && DE_FOUND="true"

# 3. Check Locale Configuration
# Look for scope='stores' and scope_id matching the store views
FR_LOCALE=""
if [ -n "$FR_STORE_ID" ]; then
    FR_LOCALE=$(magento_query "SELECT value FROM core_config_data WHERE path='general/locale/code' AND scope='stores' AND scope_id=$FR_STORE_ID" 2>/dev/null | tail -1)
fi

DE_LOCALE=""
if [ -n "$DE_STORE_ID" ]; then
    DE_LOCALE=$(magento_query "SELECT value FROM core_config_data WHERE path='general/locale/code' AND scope='stores' AND scope_id=$DE_STORE_ID" 2>/dev/null | tail -1)
fi

# 4. Check Currency Configuration
# Look for allowed currencies in default or website scope
# We check if result contains "EUR"
CURRENCY_CONFIG=$(magento_query "SELECT value FROM core_config_data WHERE path='currency/options/allow' AND (scope='default' OR scope='websites')" 2>/dev/null)
EUR_ALLOWED="false"
if echo "$CURRENCY_CONFIG" | grep -q "EUR"; then
    EUR_ALLOWED="true"
fi

# JSON Construction
GROUP_NAME_ESC=$(echo "$GROUP_NAME" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/multistore_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_group_count": ${INITIAL_GROUP_COUNT:-0},
    "current_group_count": ${CURRENT_GROUP_COUNT:-0},
    "group_found": $GROUP_FOUND,
    "group_id": "${GROUP_ID:-}",
    "group_name": "$GROUP_NAME_ESC",
    "fr_view_found": $FR_FOUND,
    "fr_store_id": "${FR_STORE_ID:-}",
    "fr_code": "${FR_CODE:-}",
    "fr_group_id": "${FR_GROUP_ID:-}",
    "fr_active": "${FR_ACTIVE:-0}",
    "fr_locale": "${FR_LOCALE:-}",
    "de_view_found": $DE_FOUND,
    "de_store_id": "${DE_STORE_ID:-}",
    "de_code": "${DE_CODE:-}",
    "de_group_id": "${DE_GROUP_ID:-}",
    "de_active": "${DE_ACTIVE:-0}",
    "de_locale": "${DE_LOCALE:-}",
    "eur_currency_allowed": $EUR_ALLOWED
}
EOF

safe_write_json "$TEMP_JSON" /tmp/multistore_result.json

echo ""
cat /tmp/multistore_result.json
echo ""
echo "=== Export Complete ==="