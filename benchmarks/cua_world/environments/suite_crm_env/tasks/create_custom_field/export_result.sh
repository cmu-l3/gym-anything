#!/bin/bash
echo "=== Exporting create_custom_field results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/create_custom_field_final.png

# 1. Check fields_meta_data table
FIELD_DATA=$(suitecrm_db_query "SELECT id, name, custom_module, type, ext1, default_value, date_modified FROM fields_meta_data WHERE name='preferred_contact_method_c' AND deleted=0 LIMIT 1")

FIELD_FOUND="false"
F_NAME=""
F_MODULE=""
F_TYPE=""
F_EXT1=""
F_DEFAULT=""

if [ -n "$FIELD_DATA" ]; then
    FIELD_FOUND="true"
    F_NAME=$(echo "$FIELD_DATA" | awk -F'\t' '{print $2}')
    F_MODULE=$(echo "$FIELD_DATA" | awk -F'\t' '{print $3}')
    F_TYPE=$(echo "$FIELD_DATA" | awk -F'\t' '{print $4}')
    F_EXT1=$(echo "$FIELD_DATA" | awk -F'\t' '{print $5}')
    F_DEFAULT=$(echo "$FIELD_DATA" | awk -F'\t' '{print $6}')
fi

# 2. Check if the column actually exists in the DB table contacts_cstm
COL_CHECK=$(suitecrm_db_query "SHOW COLUMNS FROM contacts_cstm LIKE 'preferred_contact_method_c'")
COL_EXISTS="false"
if [ -n "$COL_CHECK" ]; then
    COL_EXISTS="true"
fi

# 3. Extract the dropdown list from SuiteCRM's global PHP state
# This is much more robust than grepping files because it handles caching automatically
cat > /tmp/check_dd.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $app_list_strings;
if (isset($app_list_strings['preferred_contact_method_list'])) {
    echo json_encode($app_list_strings['preferred_contact_method_list']);
} else {
    echo "{}";
}
PHPEOF

docker cp /tmp/check_dd.php suitecrm-app:/tmp/check_dd.php
DD_JSON=$(docker exec suitecrm-app php /tmp/check_dd.php 2>/dev/null || echo "{}")
if [ -z "$DD_JSON" ]; then
    DD_JSON="{}"
fi

# 4. Compile the result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "field_found": $FIELD_FOUND,
  "name": "$(json_escape "${F_NAME}")",
  "module": "$(json_escape "${F_MODULE}")",
  "type": "$(json_escape "${F_TYPE}")",
  "dropdown_name": "$(json_escape "${F_EXT1}")",
  "default_value": "$(json_escape "${F_DEFAULT}")",
  "column_exists": $COL_EXISTS,
  "dropdown_options": $DD_JSON
}
JSONEOF
)

safe_write_result "/tmp/create_custom_field_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_custom_field_result.json"
echo "$RESULT_JSON"
echo "=== create_custom_field export complete ==="