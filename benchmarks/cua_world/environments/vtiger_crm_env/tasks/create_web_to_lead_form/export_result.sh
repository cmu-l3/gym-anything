#!/bin/bash
echo "=== Exporting create_web_to_lead_form results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

INITIAL_COUNT=$(cat /tmp/initial_webform_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_webforms" | tr -d '[:space:]')

# Query the database for the specific webform
WEBFORM_DATA=$(vtiger_db_query "SELECT id, name, targetmodule, returnurl FROM vtiger_webforms WHERE name='B2B Landing Page' LIMIT 1")

WEBFORM_FOUND="false"
W_ID=""
W_NAME=""
W_MODULE=""
W_RETURN=""

HAS_LASTNAME="0"
HAS_COMPANY="0"
HAS_EMAIL="0"
HAS_PHONE="0"

LS_FOUND="0"
LS_HIDDEN="0"
LS_DEFAULT=""

if [ -n "$WEBFORM_DATA" ]; then
    WEBFORM_FOUND="true"
    W_ID=$(echo "$WEBFORM_DATA" | awk -F'\t' '{print $1}')
    W_NAME=$(echo "$WEBFORM_DATA" | awk -F'\t' '{print $2}')
    W_MODULE=$(echo "$WEBFORM_DATA" | awk -F'\t' '{print $3}')
    W_RETURN=$(echo "$WEBFORM_DATA" | awk -F'\t' '{print $4}')

    # Check for presence of required standard fields
    HAS_LASTNAME=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_webforms_field WHERE webformid=$W_ID AND fieldname='lastname'" | tr -d '[:space:]')
    HAS_COMPANY=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_webforms_field WHERE webformid=$W_ID AND fieldname='company'" | tr -d '[:space:]')
    HAS_EMAIL=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_webforms_field WHERE webformid=$W_ID AND fieldname='email'" | tr -d '[:space:]')
    HAS_PHONE=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_webforms_field WHERE webformid=$W_ID AND fieldname='phone'" | tr -d '[:space:]')

    # Fetch Lead Source field configuration
    LEADSOURCE_DATA=$(vtiger_db_query "SELECT hidden, defaultvalue FROM vtiger_webforms_field WHERE webformid=$W_ID AND fieldname='leadsource' LIMIT 1")
    if [ -n "$LEADSOURCE_DATA" ]; then
        LS_FOUND="1"
        LS_HIDDEN=$(echo "$LEADSOURCE_DATA" | awk -F'\t' '{print $1}')
        LS_DEFAULT=$(echo "$LEADSOURCE_DATA" | awk -F'\t' '{print $2}')
    fi
fi

# Build JSON Result
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "initial_count": ${INITIAL_COUNT:-0},
  "current_count": ${CURRENT_COUNT:-0},
  "webform_found": ${WEBFORM_FOUND},
  "webform_id": "$(json_escape "${W_ID}")",
  "name": "$(json_escape "${W_NAME}")",
  "target_module": "$(json_escape "${W_MODULE}")",
  "return_url": "$(json_escape "${W_RETURN}")",
  "fields": {
    "has_lastname": ${HAS_LASTNAME:-0},
    "has_company": ${HAS_COMPANY:-0},
    "has_email": ${HAS_EMAIL:-0},
    "has_phone": ${HAS_PHONE:-0},
    "has_leadsource": ${LS_FOUND:-0}
  },
  "leadsource_config": {
    "hidden": ${LS_HIDDEN:-0},
    "default_value": "$(json_escape "${LS_DEFAULT}")"
  }
}
JSONEOF
)

safe_write_result "/tmp/create_web_to_lead_form_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_web_to_lead_form_result.json"
echo "$RESULT_JSON"
echo "=== create_web_to_lead_form export complete ==="