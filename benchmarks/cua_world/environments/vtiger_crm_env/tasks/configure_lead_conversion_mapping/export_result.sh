#!/bin/bash
echo "=== Exporting configure_lead_conversion_mapping results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/configure_mapping_final.png

# Query Lead Custom Field
LEAD_FIELD_DATA=$(vtiger_db_query "SELECT fieldid, columnname FROM vtiger_field WHERE fieldlabel='Referral Code' AND tabid=(SELECT tabid FROM vtiger_tab WHERE name='Leads' LIMIT 1) LIMIT 1")
LEAD_FID=$(echo "$LEAD_FIELD_DATA" | awk -F'\t' '{print $1}')
LEAD_COL=$(echo "$LEAD_FIELD_DATA" | awk -F'\t' '{print $2}')

# Query Contact Custom Field
CONTACT_FIELD_DATA=$(vtiger_db_query "SELECT fieldid, columnname FROM vtiger_field WHERE fieldlabel='Referral Code' AND tabid=(SELECT tabid FROM vtiger_tab WHERE name='Contacts' LIMIT 1) LIMIT 1")
CONTACT_FID=$(echo "$CONTACT_FIELD_DATA" | awk -F'\t' '{print $1}')
CONTACT_COL=$(echo "$CONTACT_FIELD_DATA" | awk -F'\t' '{print $2}')

# Check Mapping
MAPPED="false"
if [ -n "$LEAD_FID" ] && [ -n "$CONTACT_FID" ]; then
   MAPPING_CHECK=$(vtiger_db_query "SELECT 1 FROM vtiger_convertleadmapping WHERE leadfid='$LEAD_FID' AND contactfid='$CONTACT_FID' LIMIT 1" | tr -d '[:space:]')
   if [ "$MAPPING_CHECK" = "1" ]; then
       MAPPED="true"
   fi
fi

# Check if Lead was converted
LEAD_CONVERTED_STATUS=$(vtiger_db_query "SELECT converted FROM vtiger_leaddetails WHERE lastname='OConnor' AND company='OConnor Industries' ORDER BY leadid DESC LIMIT 1" | tr -d '[:space:]')
LEAD_CONVERTED="false"
if [ "$LEAD_CONVERTED_STATUS" = "1" ]; then
    LEAD_CONVERTED="true"
fi

# Check resulting Contact data
CONTACT_REF_CODE=""
if [ -n "$CONTACT_COL" ]; then
    # Query contact details and its custom fields
    CONTACT_REF_CODE=$(vtiger_db_query "SELECT cf.${CONTACT_COL} FROM vtiger_contactdetails cd INNER JOIN vtiger_contactscf cf ON cd.contactid = cf.contactid WHERE cd.lastname='OConnor' ORDER BY cd.contactid DESC LIMIT 1" | tr -d '\n' | sed 's/\r//g')
fi

# Build Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "lead_field_created": $(if [ -n "$LEAD_FID" ]; then echo "true"; else echo "false"; fi),
  "lead_field_column": "$(json_escape "${LEAD_COL:-}")",
  "contact_field_created": $(if [ -n "$CONTACT_FID" ]; then echo "true"; else echo "false"; fi),
  "contact_field_column": "$(json_escape "${CONTACT_COL:-}")",
  "fields_mapped": ${MAPPED},
  "lead_converted": ${LEAD_CONVERTED},
  "contact_referral_code": "$(json_escape "${CONTACT_REF_CODE:-}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== configure_lead_conversion_mapping export complete ==="