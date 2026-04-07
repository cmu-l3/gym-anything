#!/bin/bash
echo "=== Exporting create_vendor_record results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read variables
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_VENDOR_COUNT=$(cat /tmp/initial_vendor_count.txt 2>/dev/null || echo "0")
CURRENT_VENDOR_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_vendor" | tr -d '[:space:]')

# Query the database for the vendor record safely avoiding multiline/tab parsing issues
V_ID=$(vtiger_db_query "SELECT vendorid FROM vtiger_vendor WHERE vendorname='GreenScape Materials Co.' LIMIT 1" | tr -d '[:space:]')

VENDOR_FOUND="false"
if [ -n "$V_ID" ]; then
    VENDOR_FOUND="true"
    V_NAME=$(vtiger_db_query "SELECT vendorname FROM vtiger_vendor WHERE vendorid='$V_ID'")
    V_PHONE=$(vtiger_db_query "SELECT phone FROM vtiger_vendor WHERE vendorid='$V_ID'")
    V_EMAIL=$(vtiger_db_query "SELECT email FROM vtiger_vendor WHERE vendorid='$V_ID'")
    V_WEBSITE=$(vtiger_db_query "SELECT website FROM vtiger_vendor WHERE vendorid='$V_ID'")
    V_STREET=$(vtiger_db_query "SELECT street FROM vtiger_vendoraddress WHERE vendorid='$V_ID'")
    V_CITY=$(vtiger_db_query "SELECT city FROM vtiger_vendoraddress WHERE vendorid='$V_ID'")
    V_STATE=$(vtiger_db_query "SELECT state FROM vtiger_vendoraddress WHERE vendorid='$V_ID'")
    V_POSTAL=$(vtiger_db_query "SELECT postalcode FROM vtiger_vendoraddress WHERE vendorid='$V_ID'")
    V_COUNTRY=$(vtiger_db_query "SELECT country FROM vtiger_vendoraddress WHERE vendorid='$V_ID'")
    V_DESC=$(vtiger_db_query "SELECT description FROM vtiger_crmentity WHERE crmid='$V_ID'" | tr '\n' ' ' | tr '\r' ' ' | sed 's/  */ /g')
    V_CREATED_TIME=$(vtiger_db_query "SELECT UNIX_TIMESTAMP(createdtime) FROM vtiger_crmentity WHERE crmid='$V_ID'" | tr -d '[:space:]')
else
    V_NAME=""
    V_PHONE=""
    V_EMAIL=""
    V_WEBSITE=""
    V_STREET=""
    V_CITY=""
    V_STATE=""
    V_POSTAL=""
    V_COUNTRY=""
    V_DESC=""
    V_CREATED_TIME="0"
fi

# Build JSON result using safe escaping
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START_TIME},
  "initial_count": ${INITIAL_VENDOR_COUNT},
  "current_count": ${CURRENT_VENDOR_COUNT:-0},
  "vendor_found": ${VENDOR_FOUND},
  "vendor": {
    "id": "$(json_escape "${V_ID:-}")",
    "name": "$(json_escape "${V_NAME:-}")",
    "phone": "$(json_escape "${V_PHONE:-}")",
    "email": "$(json_escape "${V_EMAIL:-}")",
    "website": "$(json_escape "${V_WEBSITE:-}")",
    "street": "$(json_escape "${V_STREET:-}")",
    "city": "$(json_escape "${V_CITY:-}")",
    "state": "$(json_escape "${V_STATE:-}")",
    "postalcode": "$(json_escape "${V_POSTAL:-}")",
    "country": "$(json_escape "${V_COUNTRY:-}")",
    "description": "$(json_escape "${V_DESC:-}")",
    "created_timestamp": ${V_CREATED_TIME:-0}
  }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== create_vendor_record export complete ==="