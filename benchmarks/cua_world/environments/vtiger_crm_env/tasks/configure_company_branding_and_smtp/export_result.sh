#!/bin/bash
echo "=== Exporting configuration results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get Company Details from the database
ORG_DATA=$(vtiger_db_query "SELECT organizationname, address, city, state, code, country, phone, website FROM vtiger_organizationdetails LIMIT 1")

O_NAME=$(echo "$ORG_DATA" | awk -F'\t' '{print $1}')
O_ADDR=$(echo "$ORG_DATA" | awk -F'\t' '{print $2}')
O_CITY=$(echo "$ORG_DATA" | awk -F'\t' '{print $3}')
O_STATE=$(echo "$ORG_DATA" | awk -F'\t' '{print $4}')
O_CODE=$(echo "$ORG_DATA" | awk -F'\t' '{print $5}')
O_COUNTRY=$(echo "$ORG_DATA" | awk -F'\t' '{print $6}')
O_PHONE=$(echo "$ORG_DATA" | awk -F'\t' '{print $7}')
O_WEB=$(echo "$ORG_DATA" | awk -F'\t' '{print $8}')

# 2. Get SMTP details from the database (fallback empty string if from_email_field is missing in some vtiger schemas)
SMTP_DATA=$(vtiger_db_query "SELECT server, server_username, server_password, from_email_field FROM vtiger_systems WHERE server_type='email' LIMIT 1" 2>/dev/null || vtiger_db_query "SELECT server, server_username, server_password, '' FROM vtiger_systems WHERE server_type='email' LIMIT 1")

S_SERVER=$(echo "$SMTP_DATA" | awk -F'\t' '{print $1}')
S_USER=$(echo "$SMTP_DATA" | awk -F'\t' '{print $2}')
S_PASS=$(echo "$SMTP_DATA" | awk -F'\t' '{print $3}')
S_FROM=$(echo "$SMTP_DATA" | awk -F'\t' '{print $4}')

# 3. Extract core configuration directly from the config.inc.php file via PHP evaluation
CONFIG_JSON=$(docker exec vtiger-app php -r "
    include 'config.inc.php'; 
    echo json_encode([
        'helpdesk_email' => isset(\$HELPDESK_SUPPORT_EMAIL_ID) ? \$HELPDESK_SUPPORT_EMAIL_ID : '', 
        'default_module' => isset(\$default_module) ? \$default_module : '', 
        'upload_maxsize' => isset(\$upload_maxsize) ? \$upload_maxsize : ''
    ]);
" 2>/dev/null || echo "{}")

# Construct the comprehensive JSON payload
RESULT_JSON=$(cat << JSONEOF
{
  "org_name": "$(json_escape "${O_NAME:-}")",
  "org_address": "$(json_escape "${O_ADDR:-}")",
  "org_city": "$(json_escape "${O_CITY:-}")",
  "org_state": "$(json_escape "${O_STATE:-}")",
  "org_code": "$(json_escape "${O_CODE:-}")",
  "org_country": "$(json_escape "${O_COUNTRY:-}")",
  "org_phone": "$(json_escape "${O_PHONE:-}")",
  "org_website": "$(json_escape "${O_WEB:-}")",
  "smtp_server": "$(json_escape "${S_SERVER:-}")",
  "smtp_user": "$(json_escape "${S_USER:-}")",
  "smtp_pass": "$(json_escape "${S_PASS:-}")",
  "smtp_from": "$(json_escape "${S_FROM:-}")",
  "config_php": ${CONFIG_JSON:-{}},
  "timestamp": "$(date +%s)"
}
JSONEOF
)

safe_write_result "/tmp/config_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/config_task_result.json"
cat /tmp/config_task_result.json
echo "=== Export complete ==="